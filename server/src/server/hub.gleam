import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import server/ship/model
import server/vm
import shared/protocol.{
  type LogEntry, type ServerEvent, type Severity, type Subsystem,
  type SubsystemId, type VmStats, LogEntry, Logged, Offline, Snapshot,
  SubsystemUpdated, VmStats, VmUpdated,
}

/// How many journal entries are kept for new subscribers.
pub const log_limit = 200

// PURE STATE

/// What a new client needs to see: the latest of everything.
pub type State {
  State(
    ship_name: String,
    subsystems: Dict(SubsystemId, Subsystem),
    vm: VmStats,
    /// Newest first.
    log: List(LogEntry),
  )
}

/// Empty state before any subsystem has reported in.
pub fn new_state(ship_name: String) -> State {
  State(
    ship_name:,
    subsystems: dict.new(),
    vm: VmStats(
      process_count: 0,
      memory_bytes: 0,
      run_queue: 0,
      schedulers: 0,
      uptime_ms: 0,
    ),
    log: [],
  )
}

/// Folds an event into the state. `Snapshot` carries no news and is ignored.
pub fn apply(state: State, event: ServerEvent) -> State {
  case event {
    SubsystemUpdated(subsystem) ->
      State(
        ..state,
        subsystems: dict.insert(state.subsystems, subsystem.id, subsystem),
      )
    VmUpdated(vm) -> State(..state, vm:)
    Logged(entry) ->
      State(..state, log: [entry, ..state.log] |> list.take(log_limit))
    Snapshot(..) -> state
  }
}

/// The `Snapshot` event for a new subscriber: subsystems in display order,
/// journal oldest first.
pub fn snapshot(state: State) -> ServerEvent {
  Snapshot(
    ship_name: state.ship_name,
    subsystems: list.filter_map(protocol.all_subsystems, dict.get(
      state.subsystems,
      _,
    )),
    vm: state.vm,
    log: list.reverse(state.log),
  )
}

// ACTOR

/// What the hub understands.
pub type Message {
  /// Start streaming events to this subject. A `Snapshot` is sent right away.
  Subscribe(Subject(ServerEvent))
  Unsubscribe(Subject(ServerEvent))
  /// Record an event and broadcast it to every subscriber.
  Publish(ServerEvent)
  /// A subsystem process came up. Replies with how many times it has been
  /// restarted so far; the hub outlives subsystem crashes, so it keeps count.
  RegisterSubsystem(id: SubsystemId, pid: Pid, reply: Subject(Int))
  ProcessDown(process.Down)
}

type Subscriber {
  Subscriber(subject: Subject(ServerEvent), monitor: process.Monitor)
}

type Hub {
  Hub(
    core: State,
    subscribers: Dict(Pid, Subscriber),
    subsystem_pids: Dict(SubsystemId, Pid),
    restarts: Dict(SubsystemId, Int),
  )
}

/// Starts the hub, registered under `name` so that it keeps its address
/// across supervisor restarts.
pub fn start(
  name: Name(Message),
  ship_name: String,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> process.select_monitors(ProcessDown)
    Hub(
      core: new_state(ship_name),
      subscribers: dict.new(),
      subsystem_pids: dict.new(),
      restarts: dict.new(),
    )
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// The hub as a supervised child.
pub fn supervised(
  name: Name(Message),
  ship_name: String,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name, ship_name) })
}

fn handle_message(hub: Hub, message: Message) -> actor.Next(Hub, Message) {
  case message {
    Subscribe(subject) -> actor.continue(subscribe(hub, subject))
    Unsubscribe(subject) -> actor.continue(unsubscribe(hub, subject))
    Publish(event) -> actor.continue(publish(hub, event))
    RegisterSubsystem(id:, pid:, reply:) -> {
      let #(hub, restarts) = register_subsystem(hub, id, pid)
      process.send(reply, restarts)
      actor.continue(hub)
    }
    ProcessDown(process.ProcessDown(pid:, ..)) ->
      actor.continue(handle_down(hub, pid))
    ProcessDown(process.PortDown(..)) -> actor.continue(hub)
  }
}

fn subscribe(hub: Hub, subject: Subject(ServerEvent)) -> Hub {
  case process.subject_owner(subject) {
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      process.send(subject, snapshot(hub.core))
      Hub(
        ..hub,
        subscribers: dict.insert(
          hub.subscribers,
          pid,
          Subscriber(subject, monitor),
        ),
      )
    }
    Error(Nil) -> hub
  }
}

fn unsubscribe(hub: Hub, subject: Subject(ServerEvent)) -> Hub {
  case process.subject_owner(subject) {
    Ok(pid) -> remove_subscriber(hub, pid)
    Error(Nil) -> hub
  }
}

fn remove_subscriber(hub: Hub, pid: Pid) -> Hub {
  case dict.get(hub.subscribers, pid) {
    Ok(Subscriber(monitor:, ..)) -> {
      process.demonitor_process(monitor)
      Hub(..hub, subscribers: dict.delete(hub.subscribers, pid))
    }
    Error(Nil) -> hub
  }
}

fn publish(hub: Hub, event: ServerEvent) -> Hub {
  case event {
    Snapshot(..) -> hub
    _ -> {
      dict.each(hub.subscribers, fn(_, subscriber) {
        process.send(subscriber.subject, event)
      })
      Hub(..hub, core: apply(hub.core, event))
    }
  }
}

fn register_subsystem(hub: Hub, id: SubsystemId, pid: Pid) -> #(Hub, Int) {
  // Seen before means this is a restart.
  let restarts = case dict.get(hub.subsystem_pids, id) {
    Ok(_) -> result.unwrap(dict.get(hub.restarts, id), 0) + 1
    Error(Nil) -> 0
  }
  process.monitor(pid)
  let hub =
    Hub(
      ..hub,
      subsystem_pids: dict.insert(hub.subsystem_pids, id, pid),
      restarts: dict.insert(hub.restarts, id, restarts),
    )
  #(hub, restarts)
}

/// A monitored process died: either a client went away, or a subsystem
/// crashed (in which case the supervisor is already restarting it).
fn handle_down(hub: Hub, pid: Pid) -> Hub {
  case dict.has_key(hub.subscribers, pid) {
    True -> Hub(..hub, subscribers: dict.delete(hub.subscribers, pid))
    False ->
      case find_subsystem(hub, pid) {
        Some(id) -> subsystem_failed(hub, id)
        // A stale pid from an earlier incarnation: already replaced.
        None -> hub
      }
  }
}

fn find_subsystem(hub: Hub, pid: Pid) -> option.Option(SubsystemId) {
  dict.to_list(hub.subsystem_pids)
  |> list.find(fn(entry) { entry.1 == pid })
  |> option.from_result
  |> option.map(fn(entry) { entry.0 })
}

fn subsystem_failed(hub: Hub, id: SubsystemId) -> Hub {
  let #(severity, text) = model.failure_log()
  let hub = case dict.get(hub.core.subsystems, id) {
    Ok(subsystem) ->
      publish(
        hub,
        SubsystemUpdated(protocol.Subsystem(..subsystem, status: Offline)),
      )
    Error(Nil) -> hub
  }
  publish(hub, Logged(entry(severity, protocol.subsystem_name(id), text)))
}

fn entry(severity: Severity, source: String, message: String) -> LogEntry {
  LogEntry(at_ms: vm.now_ms(), severity:, source:, message:)
}

// CLIENT API

/// Broadcasts an event through the hub.
pub fn publish_event(hub: Subject(Message), event: ServerEvent) -> Nil {
  process.send(hub, Publish(event))
}

/// Appends a journal entry stamped with the current time.
pub fn log(
  hub: Subject(Message),
  severity: Severity,
  source: String,
  message: String,
) -> Nil {
  publish_event(hub, Logged(entry(severity, source, message)))
}

/// Registers the calling process as the subsystem `id`; returns its restart count.
pub fn register_subsystem_process(
  hub: Subject(Message),
  id: SubsystemId,
) -> Int {
  process.call(hub, 1000, fn(reply) {
    RegisterSubsystem(id:, pid: process.self(), reply:)
  })
}
