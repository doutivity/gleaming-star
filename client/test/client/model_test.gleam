import client/model.{Connecting}
import client/route.{Dashboard}
import client/ui/animator
import client/ui/log
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import shared/protocol.{
  type LogEntry, type Subsystem, Comms, Info, LogEntry, Logged, Nominal, Offline,
  Reactor, Rebooting, Snapshot, Subsystem, SubsystemUpdated, VmStats, VmUpdated,
}

fn subsystem(id, status) -> Subsystem {
  Subsystem(id:, status:, power: 50, load: 50, temperature: 50, restarts: 0)
}

fn entry(n: Int) -> LogEntry {
  LogEntry(at_ms: n, severity: Info, source: "t", message: int.to_string(n))
}

fn entries(model: model.Model) -> List(LogEntry) {
  list.map(model.log, fn(line) { line.entry })
}

pub fn new_model_is_connecting_and_empty_test() {
  let model = model.new(Dashboard)
  assert model.link == Connecting
  assert model.attempts == 0
  assert model.socket == None
  assert model.vm == None
  assert model.log == []
  assert model.ordered_subsystems(model) == []
  assert model.is_animating(model) == False
}

pub fn snapshot_replaces_everything_test() {
  let vm = VmStats(1, 2, 3, 4, 5)
  let model =
    model.new(Dashboard)
    |> model.apply_event(SubsystemUpdated(subsystem(Comms, Offline)))
    |> model.apply_event(
      Snapshot(
        ship_name: "ISV TEST",
        subsystems: [subsystem(Reactor, Nominal)],
        vm:,
        log: [entry(1), entry(2)],
      ),
    )
  assert model.ship_name == "ISV TEST"
  assert model.vm == Some(vm)
  assert entries(model) == [entry(1), entry(2)]
  assert model.ordered_subsystems(model) == [subsystem(Reactor, Nominal)]
  assert model.memory_history == [2]
  assert model.process_history == [1]
}

pub fn snapshot_lines_are_not_animated_test() {
  let model =
    model.apply_event(
      model.new(Dashboard),
      Snapshot(ship_name: "S", subsystems: [], vm: VmStats(0, 0, 0, 0, 0), log: [
        entry(1),
        entry(2),
      ]),
    )
  assert animator.lookup(model.anims, log.anim_key(0)) == animator.Entered
  assert animator.lookup(model.anims, log.anim_key(1)) == animator.Entered
  assert list.map(model.log, fn(line) { line.id }) == [0, 1]
  assert model.next_line_id == 2
}

pub fn subsystem_updated_replaces_by_id_test() {
  let model =
    model.new(Dashboard)
    |> model.apply_event(SubsystemUpdated(subsystem(Reactor, Rebooting)))
    |> model.apply_event(SubsystemUpdated(subsystem(Reactor, Nominal)))
  assert dict.get(model.subsystems, Reactor) == Ok(subsystem(Reactor, Nominal))
  assert dict.size(model.subsystems) == 1
}

pub fn subsystems_are_in_display_order_test() {
  let model =
    model.new(Dashboard)
    |> model.apply_event(SubsystemUpdated(subsystem(Comms, Nominal)))
    |> model.apply_event(SubsystemUpdated(subsystem(Reactor, Nominal)))
  assert list.map(model.ordered_subsystems(model), fn(s) { s.id })
    == [Reactor, Comms]
}

pub fn vm_updated_records_history_test() {
  let model =
    model.new(Dashboard)
    |> model.apply_event(VmUpdated(VmStats(10, 100, 0, 1, 0)))
    |> model.apply_event(VmUpdated(VmStats(11, 200, 0, 1, 0)))
  assert model.vm == Some(VmStats(11, 200, 0, 1, 0))
  assert model.process_history == [10, 11]
  assert model.memory_history == [100, 200]
}

pub fn history_keeps_the_latest_60_test() {
  let model =
    int.range(from: 1, to: 101, with: model.new(Dashboard), run: fn(model, n) {
      model.apply_event(model, VmUpdated(VmStats(n, n, 0, 1, 0)))
    })
  assert list.length(model.process_history) == 60
  assert list.first(model.process_history) == Ok(41)
  assert list.last(model.process_history) == Ok(100)
}

pub fn logged_appends_and_keeps_latest_200_test() {
  let model =
    int.range(from: 1, to: 251, with: model.new(Dashboard), run: fn(model, n) {
      model.apply_event(model, Logged(entry(n)))
    })
  assert list.length(model.log) == model.log_limit
  assert list.first(entries(model)) == Ok(entry(51))
  assert list.last(entries(model)) == Ok(entry(250))
}

pub fn logged_line_starts_deciphering_test() {
  let model = model.apply_event(model.new(Dashboard), Logged(entry(1)))
  assert animator.lookup(model.anims, log.anim_key(0)) == animator.Entering(0.0)
  assert model.is_animating(model)
  assert model.next_line_id == 1
}

pub fn oversized_snapshot_log_is_trimmed_test() {
  let log =
    int.range(from: 1, to: 251, with: [], run: fn(acc, n) { [entry(n), ..acc] })
    |> list.reverse
  let model =
    model.apply_event(
      model.new(Dashboard),
      Snapshot(ship_name: "S", subsystems: [], vm: VmStats(0, 0, 0, 0, 0), log:),
    )
  assert list.length(model.log) == model.log_limit
  assert list.last(entries(model)) == Ok(entry(250))
}

// Failure tracking

fn with_restarts(status, restarts) -> Subsystem {
  Subsystem(..subsystem(Reactor, status), restarts:)
}

fn update(model, status, restarts) {
  model.apply_event(model, SubsystemUpdated(with_restarts(status, restarts)))
}

pub fn offline_marks_the_subsystem_failed_test() {
  let model =
    update(model.new(Dashboard), Nominal, 0)
    |> update(Offline, 0)
  assert model.is_failed(model, Reactor)
}

pub fn failure_lasts_through_the_reboot_until_nominal_test() {
  let model =
    update(model.new(Dashboard), Nominal, 0)
    |> update(Offline, 0)
    // The supervisor's replacement comes up rebooting, restarts + 1.
    |> update(Rebooting, 1)
  assert model.is_failed(model, Reactor)
  let model = update(model, Nominal, 1)
  assert model.is_failed(model, Reactor) == False
}

pub fn a_raised_restart_count_alone_marks_a_failure_test() {
  // If the Offline update was missed, the restart count still gives it away.
  let model =
    update(model.new(Dashboard), Nominal, 0)
    |> update(Rebooting, 1)
  assert model.is_failed(model, Reactor)
}

pub fn a_controlled_reboot_is_not_a_failure_test() {
  let model =
    update(model.new(Dashboard), Nominal, 0)
    |> update(Rebooting, 0)
  assert model.is_failed(model, Reactor) == False
}

pub fn first_sight_of_a_rebooting_subsystem_is_not_a_failure_test() {
  // A restarted hub may report restarts > 0 with nothing to compare against.
  let model = update(model.new(Dashboard), Rebooting, 2)
  assert model.is_failed(model, Reactor) == False
}

pub fn failure_and_recovery_decipher_the_title_test() {
  let model = update(model.new(Dashboard), Nominal, 0)
  assert model.is_animating(model) == False
  let model = update(model, Offline, 0)
  assert animator.lookup(model.anims, model.title_key(Reactor))
    == animator.Entering(0.0)
  // Already failed: further updates do not restart the animation.
  let model = model.Model(..model, anims: dict.new())
  let model = update(model, Rebooting, 1)
  assert model.is_animating(model) == False
  // Recovery restarts it to bring the name back.
  let model = update(model, Nominal, 1)
  assert animator.lookup(model.anims, model.title_key(Reactor))
    == animator.Entering(0.0)
}

pub fn degraded_alone_is_not_a_failure_test() {
  let model =
    update(model.new(Dashboard), Nominal, 0)
    |> update(protocol.Degraded("OVERHEAT"), 0)
  assert model.is_failed(model, Reactor) == False
}

pub fn snapshot_resets_failures_to_what_is_offline_test() {
  let model =
    update(model.new(Dashboard), Nominal, 0)
    |> update(Offline, 0)
    |> model.apply_event(
      Snapshot(
        ship_name: "S",
        subsystems: [with_restarts(Nominal, 1)],
        vm: VmStats(0, 0, 0, 0, 0),
        log: [],
      ),
    )
  assert set.size(model.failed) == 0
  let model =
    model.apply_event(
      model,
      Snapshot(
        ship_name: "S",
        subsystems: [with_restarts(Offline, 1)],
        vm: VmStats(0, 0, 0, 0, 0),
        log: [],
      ),
    )
  assert model.is_failed(model, Reactor)
}

pub fn ship_name_is_deciphered_when_it_arrives_test() {
  let snapshot = fn(name) {
    Snapshot(
      ship_name: name,
      subsystems: [],
      vm: VmStats(0, 0, 0, 0, 0),
      log: [],
    )
  }
  let model = model.apply_event(model.new(Dashboard), snapshot("ISV TEST"))
  assert animator.lookup(model.anims, model.ship_name_key)
    == animator.Entering(0.0)
  // The same name again (after a reconnect) does not replay it.
  let model = model.Model(..model, anims: dict.new())
  let model = model.apply_event(model, snapshot("ISV TEST"))
  assert model.is_animating(model) == False
}
