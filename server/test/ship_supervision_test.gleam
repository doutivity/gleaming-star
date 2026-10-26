import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/supervision
import server/hub
import server/names
import server/ship/subsystem
import server/ship/supervisor as ship_supervisor
import shared/protocol.{
  type ServerEvent, Critical, LogEntry, Logged, Nominal, Offline, Reactor,
  Rebooting, Shields, Snapshot, Subsystem, SubsystemUpdated,
}

/// Receives events until one matches, failing the test after 5 s of silence.
fn await(
  events: Subject(ServerEvent),
  matching: fn(ServerEvent) -> Bool,
) -> ServerEvent {
  let assert Ok(event) = process.receive(events, 5000)
  case matching(event) {
    True -> event
    False -> await(events, matching)
  }
}

fn reactor_is(status, restarts) -> fn(ServerEvent) -> Bool {
  fn(event) {
    case event {
      SubsystemUpdated(Subsystem(id: Reactor, status: s, restarts: r, ..)) ->
        s == status && r == restarts
      _ -> False
    }
  }
}

fn start_ship() -> #(names.Names, Subject(ServerEvent)) {
  let names = names.new()
  let assert Ok(_) = hub.start(names.hub, "ISV TEST")
  let assert Ok(_) = ship_supervisor.supervised(names).start()
  let events = process.new_subject()
  process.send(names.hub_subject(names), hub.Subscribe(events))
  #(names, events)
}

pub fn all_subsystems_boot_to_nominal_test() {
  let #(_names, events) = start_ship()
  let assert Snapshot(..) = await(events, fn(e) { is_snapshot(e) })
  list.each(protocol.all_subsystems, fn(id) {
    let assert SubsystemUpdated(_) =
      await(events, fn(event) {
        case event {
          SubsystemUpdated(Subsystem(id: got, status: Nominal, ..)) -> got == id
          _ -> False
        }
      })
  })
}

pub fn injected_fault_is_recovered_by_the_supervisor_test() {
  let #(names, events) = start_ship()
  let _ = await(events, reactor_is(Nominal, 0))

  let assert Ok(Nil) =
    names.send_to_subsystem(names, Reactor, subsystem.CrashNow)

  // The hub notices the crash, then the supervisor brings a new actor up with
  // restarts = 1, which reboots back to nominal.
  let _ = await(events, reactor_is(Offline, 0))
  let assert Logged(LogEntry(severity: Critical, ..)) =
    await(events, fn(event) {
      case event {
        Logged(LogEntry(severity: Critical, ..)) -> True
        _ -> False
      }
    })
  let _ = await(events, reactor_is(Rebooting, 1))
  let _ = await(events, reactor_is(Nominal, 1))
}

pub fn other_subsystems_survive_a_crash_test() {
  let #(names, events) = start_ship()
  let _ = await(events, reactor_is(Nominal, 0))
  let assert Ok(Nil) =
    names.send_to_subsystem(names, Reactor, subsystem.CrashNow)
  let _ = await(events, reactor_is(Nominal, 1))

  // Shields never restarted: still reachable and still on its first life.
  let assert Ok(Nil) =
    names.send_to_subsystem(names, Shields, subsystem.SetPowerTo(33))
  let _ =
    await(events, fn(event) {
      case event {
        SubsystemUpdated(Subsystem(id: Shields, power: 33, restarts: 0, ..)) ->
          True
        _ -> False
      }
    })
}

pub fn repeated_faults_do_not_take_the_ship_down_test() {
  let #(names, events) = start_ship()
  let _ = await(events, reactor_is(Nominal, 0))
  int.range(from: 1, to: 6, with: Nil, run: fn(_, n) {
    let assert Ok(Nil) =
      names.send_to_subsystem(names, Reactor, subsystem.CrashNow)
    let _ = await(events, reactor_is(Rebooting, n))
    Nil
  })
}

pub fn commands_to_a_missing_subsystem_are_dropped_test() {
  // No ship started: nothing is registered under these names.
  let names = names.new()
  assert names.send_to_subsystem(names, Reactor, subsystem.RebootNow)
    == Error(Nil)
}

fn is_snapshot(event: ServerEvent) -> Bool {
  case event {
    Snapshot(..) -> True
    _ -> False
  }
}

pub fn supervised_spec_is_a_supervisor_child_test() {
  let spec = ship_supervisor.supervised(names.new())
  assert spec.child_type == supervision.Supervisor
}
