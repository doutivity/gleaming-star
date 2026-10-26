import gleam/list
import gleeunit
import shared/codec
import shared/protocol.{
  type ClientCommand, type ServerEvent, Degraded, InjectFault, LogEntry, Logged,
  Nominal, Offline, Reactor, Reboot, Rebooting, SetPower, Shields, Snapshot,
  Subsystem, SubsystemUpdated, VmStats, VmUpdated,
}

pub fn main() -> Nil {
  gleeunit.main()
}

fn sample_vm() -> protocol.VmStats {
  VmStats(
    process_count: 312,
    memory_bytes: 48_234_496,
    run_queue: 1,
    schedulers: 8,
    uptime_ms: 123_456,
  )
}

fn sample_subsystem(
  id: protocol.SubsystemId,
  status: protocol.Status,
) -> protocol.Subsystem {
  Subsystem(id:, status:, power: 80, load: 42, temperature: 61, restarts: 3)
}

fn sample_entry() -> protocol.LogEntry {
  LogEntry(
    at_ms: 1000,
    severity: protocol.Warning,
    source: "reactor",
    message: "CORE TEMP \"HIGH\" — line\nbreak",
  )
}

fn assert_event_roundtrip(event: ServerEvent) {
  assert codec.decode_event(codec.encode_event(event)) == Ok(event)
}

fn assert_command_roundtrip(command: ClientCommand) {
  assert codec.decode_command(codec.encode_command(command)) == Ok(command)
}

// ServerEvent roundtrips

pub fn snapshot_roundtrip_test() {
  assert_event_roundtrip(
    Snapshot(
      ship_name: "ISV GLEAMING STAR",
      subsystems: list.map(protocol.all_subsystems, sample_subsystem(_, Nominal)),
      vm: sample_vm(),
      log: [sample_entry()],
    ),
  )
}

pub fn empty_snapshot_roundtrip_test() {
  assert_event_roundtrip(
    Snapshot(ship_name: "", subsystems: [], vm: sample_vm(), log: []),
  )
}

pub fn subsystem_updated_roundtrip_test() {
  assert_event_roundtrip(SubsystemUpdated(sample_subsystem(Shields, Nominal)))
}

pub fn vm_updated_roundtrip_test() {
  assert_event_roundtrip(VmUpdated(sample_vm()))
}

pub fn logged_roundtrip_test() {
  assert_event_roundtrip(Logged(sample_entry()))
}

// Nested types

pub fn every_status_roundtrip_test() {
  [Nominal, Degraded(reason: "OVERHEAT"), Offline, Rebooting]
  |> list.each(fn(status) {
    assert_event_roundtrip(SubsystemUpdated(sample_subsystem(Reactor, status)))
  })
}

pub fn every_subsystem_id_roundtrip_test() {
  list.each(protocol.all_subsystems, fn(id) {
    assert_event_roundtrip(SubsystemUpdated(sample_subsystem(id, Nominal)))
  })
}

pub fn every_severity_roundtrip_test() {
  [protocol.Info, protocol.Warning, protocol.Critical]
  |> list.each(fn(severity) {
    assert_event_roundtrip(
      Logged(LogEntry(at_ms: 0, severity:, source: "x", message: "y")),
    )
  })
}

// ClientCommand roundtrips

pub fn inject_fault_roundtrip_test() {
  list.each(protocol.all_subsystems, fn(id) {
    assert_command_roundtrip(InjectFault(id))
  })
}

pub fn reboot_roundtrip_test() {
  list.each(protocol.all_subsystems, fn(id) {
    assert_command_roundtrip(Reboot(id))
  })
}

pub fn set_power_roundtrip_test() {
  assert_command_roundtrip(SetPower(Shields, level: 75))
  assert_command_roundtrip(SetPower(Reactor, level: -5))
}

// Wire format

pub fn command_wire_format_test() {
  assert codec.encode_command(SetPower(Shields, level: 75))
    == "{\"type\":\"set_power\",\"id\":\"shields\",\"level\":75}"
  assert codec.encode_command(InjectFault(protocol.LifeSupport))
    == "{\"type\":\"inject_fault\",\"id\":\"life_support\"}"
}

pub fn event_wire_format_test() {
  assert codec.encode_event(Logged(sample_entry()))
    == "{\"type\":\"logged\",\"entry\":{\"at_ms\":1000,\"severity\":\"warning\",\"source\":\"reactor\",\"message\":\"CORE TEMP \\\"HIGH\\\" — line\\nbreak\"}}"
}

// Invalid input is an error, never a crash

pub fn decode_rejects_invalid_json_test() {
  let assert Error(_) = codec.decode_command("not json")
  let assert Error(_) = codec.decode_event("")
}

pub fn decode_rejects_unknown_type_test() {
  let assert Error(_) = codec.decode_command("{\"type\":\"self_destruct\"}")
  let assert Error(_) = codec.decode_event("{\"type\":\"nope\"}")
}

pub fn decode_rejects_unknown_subsystem_test() {
  let assert Error(_) =
    codec.decode_command("{\"type\":\"reboot\",\"id\":\"warp_core\"}")
}

pub fn decode_rejects_missing_or_mistyped_fields_test() {
  let assert Error(_) = codec.decode_command("{\"type\":\"reboot\"}")
  let assert Error(_) =
    codec.decode_command(
      "{\"type\":\"set_power\",\"id\":\"shields\",\"level\":\"high\"}",
    )
  let assert Error(_) = codec.decode_command("[]")
}

// Helpers

pub fn subsystem_name_test() {
  assert protocol.subsystem_name(protocol.LifeSupport) == "LIFE SUPPORT"
  assert list.map(protocol.all_subsystems, protocol.subsystem_name)
    == ["REACTOR", "SHIELDS", "NAVIGATION", "COMMS", "LIFE SUPPORT"]
}
