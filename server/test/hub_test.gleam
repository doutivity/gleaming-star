import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import server/hub
import shared/protocol.{
  type LogEntry, type ServerEvent, type Subsystem, Comms, Critical, Info,
  LogEntry, Logged, Nominal, Offline, Reactor, Rebooting, Snapshot, Subsystem,
  SubsystemUpdated, VmStats, VmUpdated,
}

fn subsystem(id, status) -> Subsystem {
  Subsystem(id:, status:, power: 50, load: 50, temperature: 50, restarts: 0)
}

fn entry(n: Int) -> LogEntry {
  LogEntry(at_ms: n, severity: Info, source: "t", message: "m")
}

// Pure state

pub fn apply_subsystem_updated_replaces_test() {
  let state =
    hub.new_state("S")
    |> hub.apply(SubsystemUpdated(subsystem(Reactor, Rebooting)))
    |> hub.apply(SubsystemUpdated(subsystem(Reactor, Nominal)))
  assert dict.get(state.subsystems, Reactor) == Ok(subsystem(Reactor, Nominal))
}

pub fn apply_vm_test() {
  let vm = VmStats(1, 2, 3, 4, 5)
  assert hub.apply(hub.new_state("S"), VmUpdated(vm)).vm == vm
}

pub fn log_keeps_the_latest_200_test() {
  let state =
    int.range(from: 1, to: 251, with: hub.new_state("S"), run: fn(state, n) {
      hub.apply(state, Logged(entry(n)))
    })
  let assert Snapshot(log:, ..) = hub.snapshot(state)
  assert list.length(log) == hub.log_limit
  // Oldest first, and the first 50 were dropped.
  assert list.first(log) == Ok(entry(51))
  assert list.last(log) == Ok(entry(250))
}

pub fn snapshot_orders_subsystems_for_display_test() {
  let state =
    hub.new_state("ISV TEST")
    |> hub.apply(SubsystemUpdated(subsystem(Comms, Nominal)))
    |> hub.apply(SubsystemUpdated(subsystem(Reactor, Nominal)))
  let assert Snapshot(ship_name:, subsystems:, ..) = hub.snapshot(state)
  assert ship_name == "ISV TEST"
  assert list.map(subsystems, fn(s) { s.id }) == [Reactor, Comms]
}

pub fn apply_ignores_snapshot_test() {
  let state = hub.new_state("S")
  assert hub.apply(state, hub.snapshot(state)) == state
}

// Actor

fn start_hub() -> Subject(hub.Message) {
  let name = process.new_name("hub_test")
  let assert Ok(started) = hub.start(name, "ISV TEST")
  started.data
}

fn expect(events: Subject(ServerEvent)) -> ServerEvent {
  let assert Ok(event) = process.receive(events, 2000)
  event
}

pub fn subscriber_gets_snapshot_then_live_events_test() {
  let hub = start_hub()
  let events = process.new_subject()
  process.send(hub, hub.Subscribe(events))
  let assert Snapshot(ship_name: "ISV TEST", subsystems: [], log: [], ..) =
    expect(events)

  hub.log(hub, Info, "src", "hello")
  let assert Logged(LogEntry(source: "src", message: "hello", ..)) =
    expect(events)
}

pub fn late_subscriber_sees_history_test() {
  let hub = start_hub()
  hub.publish_event(hub, SubsystemUpdated(subsystem(Reactor, Nominal)))
  hub.log(hub, Info, "src", "earlier")

  let events = process.new_subject()
  process.send(hub, hub.Subscribe(events))
  let assert Snapshot(subsystems: [Subsystem(id: Reactor, ..)], log: [_], ..) =
    expect(events)
}

pub fn unsubscribed_gets_nothing_test() {
  let hub = start_hub()
  let events = process.new_subject()
  process.send(hub, hub.Subscribe(events))
  let assert Snapshot(..) = expect(events)
  process.send(hub, hub.Unsubscribe(events))
  hub.log(hub, Info, "src", "unheard")
  assert process.receive(events, 200) == Error(Nil)
}

pub fn register_counts_restarts_test() {
  let hub = start_hub()
  assert hub.register_subsystem_process(hub, Reactor) == 0
  // A second process registering under the same id is a restart.
  let reply = process.new_subject()
  process.spawn(fn() {
    process.send(reply, hub.register_subsystem_process(hub, Reactor))
    process.sleep(500)
  })
  assert process.receive(reply, 1000) == Ok(1)
  assert hub.register_subsystem_process(hub, Comms) == 0
}

pub fn crashed_subsystem_is_reported_offline_test() {
  let hub = start_hub()
  hub.publish_event(hub, SubsystemUpdated(subsystem(Reactor, Nominal)))
  let events = process.new_subject()
  process.send(hub, hub.Subscribe(events))
  let assert Snapshot(..) = expect(events)

  process.spawn_unlinked(fn() {
    let _ = hub.register_subsystem_process(hub, Reactor)
    panic as "boom"
  })

  let assert SubsystemUpdated(Subsystem(id: Reactor, status: Offline, ..)) =
    expect(events)
  let assert Logged(LogEntry(severity: Critical, source: "REACTOR", ..)) =
    expect(events)
}

pub fn dead_subscriber_is_dropped_test() {
  let hub = start_hub()
  let reply = process.new_subject()
  process.spawn_unlinked(fn() {
    let events = process.new_subject()
    process.send(hub, hub.Subscribe(events))
    process.send(reply, process.receive(events, 1000))
  })
  let assert Ok(Ok(Snapshot(..))) = process.receive(reply, 2000)
  // The hub must survive publishing after the subscriber has exited.
  hub.log(hub, Info, "src", "still alive")
  let events = process.new_subject()
  process.send(hub, hub.Subscribe(events))
  let assert Snapshot(log: [_], ..) = expect(events)
}
