import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import server/hub
import server/ship/model
import shared/protocol.{
  type ClientCommand, type Subsystem, type SubsystemId, Info, InjectFault,
  Reboot, SetPower, SubsystemUpdated,
}

const tick_ms = 500

const boot_ms = 1500

/// What a subsystem actor understands.
pub type Message {
  /// Periodic simulation step.
  Tick
  /// The boot sequence has finished.
  BootComplete
  /// Crash on purpose; recovery is the supervisor's job.
  CrashNow
  /// Controlled reboot, no crash.
  RebootNow
  SetPowerTo(level: Int)
}

type State {
  State(self: Subject(Message), hub: Subject(hub.Message), data: Subsystem)
}

/// Which subsystem a client command is for, and the message to deliver to it.
pub fn route_command(command: ClientCommand) -> #(SubsystemId, Message) {
  case command {
    InjectFault(id) -> #(id, CrashNow)
    Reboot(id) -> #(id, RebootNow)
    SetPower(id, level) -> #(id, SetPowerTo(level))
  }
}

/// Starts the actor for subsystem `id`, registered under `name`.
pub fn start(
  id: SubsystemId,
  name: Name(Message),
  hub: Subject(hub.Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(self) {
    let restarts = hub.register_subsystem_process(hub, id)
    let data = model.initial(id, restarts)
    let source = protocol.subsystem_name(id)
    hub.publish_event(hub, SubsystemUpdated(data))
    case restarts {
      0 -> hub.log(hub, Info, source, "BOOT SEQUENCE INITIATED")
      n ->
        hub.log(
          hub,
          Info,
          source,
          "RESTARTED BY SUPERVISOR — RESTART #" <> int.to_string(n),
        )
    }
    process.send_after(self, boot_ms, BootComplete)
    process.send_after(self, tick_ms, Tick)
    State(self:, hub:, data:)
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
}

/// The subsystem as a supervised child.
pub fn supervised(
  id: SubsystemId,
  name: Name(Message),
  hub: Subject(hub.Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(id, name, hub) })
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Tick -> {
      process.send_after(state.self, tick_ms, Tick)
      let next = model.drift(state.data, int.random(11) - 5, int.random(3) - 1)
      actor.continue(update(state, next))
    }
    BootComplete ->
      actor.continue(update(state, model.boot_complete(state.data)))
    CrashNow -> panic as "injected fault"
    RebootNow -> {
      hub.log(
        state.hub,
        Info,
        protocol.subsystem_name(state.data.id),
        "CONTROLLED REBOOT",
      )
      process.send_after(state.self, boot_ms, BootComplete)
      actor.continue(update(state, model.reboot(state.data)))
    }
    SetPowerTo(level) -> {
      let next = model.set_power(state.data, level)
      case next.power == state.data.power {
        True -> Nil
        False ->
          hub.log(
            state.hub,
            Info,
            protocol.subsystem_name(next.id),
            "POWER SET TO " <> int.to_string(next.power) <> "%",
          )
      }
      actor.continue(update(state, next))
    }
  }
}

/// Stores the new data, publishing it (and a journal line for status changes)
/// only if something actually changed.
fn update(state: State, next: Subsystem) -> State {
  case next == state.data {
    True -> state
    False -> {
      hub.publish_event(state.hub, SubsystemUpdated(next))
      case model.transition_log(state.data, next) {
        Some(#(severity, text)) ->
          hub.log(state.hub, severity, protocol.subsystem_name(next.id), text)
        None -> Nil
      }
      State(..state, data: next)
    }
  }
}
