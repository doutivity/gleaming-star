import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import shared/protocol.{
  type ClientCommand, type LogEntry, type ServerEvent, type Severity,
  type Status, type Subsystem, type SubsystemId, type VmStats, Comms, Critical,
  Degraded, Info, InjectFault, LifeSupport, LogEntry, Logged, Navigation,
  Nominal, Offline, Reactor, Reboot, Rebooting, SetPower, Shields, Snapshot,
  Subsystem, SubsystemUpdated, VmStats, VmUpdated, Warning,
}

// ENCODING

/// Encodes a server event as `{"type": "...", ...}`.
pub fn encode_event(event: ServerEvent) -> String {
  event_to_json(event) |> json.to_string
}

/// Encodes a client command as `{"type": "...", ...}`.
pub fn encode_command(command: ClientCommand) -> String {
  command_to_json(command) |> json.to_string
}

/// Converts a server event to a JSON value.
pub fn event_to_json(event: ServerEvent) -> Json {
  case event {
    Snapshot(ship_name:, subsystems:, vm:, log:) ->
      json.object([
        #("type", json.string("snapshot")),
        #("ship_name", json.string(ship_name)),
        #("subsystems", json.array(subsystems, subsystem_to_json)),
        #("vm", vm_to_json(vm)),
        #("log", json.array(log, log_entry_to_json)),
      ])
    SubsystemUpdated(subsystem) ->
      json.object([
        #("type", json.string("subsystem_updated")),
        #("subsystem", subsystem_to_json(subsystem)),
      ])
    VmUpdated(vm) ->
      json.object([
        #("type", json.string("vm_updated")),
        #("vm", vm_to_json(vm)),
      ])
    Logged(entry) ->
      json.object([
        #("type", json.string("logged")),
        #("entry", log_entry_to_json(entry)),
      ])
  }
}

/// Converts a client command to a JSON value.
pub fn command_to_json(command: ClientCommand) -> Json {
  case command {
    InjectFault(id) ->
      json.object([
        #("type", json.string("inject_fault")),
        #("id", subsystem_id_to_json(id)),
      ])
    Reboot(id) ->
      json.object([
        #("type", json.string("reboot")),
        #("id", subsystem_id_to_json(id)),
      ])
    SetPower(id, level) ->
      json.object([
        #("type", json.string("set_power")),
        #("id", subsystem_id_to_json(id)),
        #("level", json.int(level)),
      ])
  }
}

fn subsystem_id_to_json(id: SubsystemId) -> Json {
  json.string(case id {
    Reactor -> "reactor"
    Shields -> "shields"
    Navigation -> "navigation"
    Comms -> "comms"
    LifeSupport -> "life_support"
  })
}

fn status_to_json(status: Status) -> Json {
  case status {
    Nominal -> json.object([#("type", json.string("nominal"))])
    Degraded(reason:) ->
      json.object([
        #("type", json.string("degraded")),
        #("reason", json.string(reason)),
      ])
    Offline -> json.object([#("type", json.string("offline"))])
    Rebooting -> json.object([#("type", json.string("rebooting"))])
  }
}

fn subsystem_to_json(subsystem: Subsystem) -> Json {
  json.object([
    #("id", subsystem_id_to_json(subsystem.id)),
    #("status", status_to_json(subsystem.status)),
    #("power", json.int(subsystem.power)),
    #("load", json.int(subsystem.load)),
    #("temperature", json.int(subsystem.temperature)),
    #("restarts", json.int(subsystem.restarts)),
  ])
}

fn vm_to_json(vm: VmStats) -> Json {
  json.object([
    #("process_count", json.int(vm.process_count)),
    #("memory_bytes", json.int(vm.memory_bytes)),
    #("run_queue", json.int(vm.run_queue)),
    #("schedulers", json.int(vm.schedulers)),
    #("uptime_ms", json.int(vm.uptime_ms)),
  ])
}

fn severity_to_json(severity: Severity) -> Json {
  json.string(case severity {
    Info -> "info"
    Warning -> "warning"
    Critical -> "critical"
  })
}

fn log_entry_to_json(entry: LogEntry) -> Json {
  json.object([
    #("at_ms", json.int(entry.at_ms)),
    #("severity", severity_to_json(entry.severity)),
    #("source", json.string(entry.source)),
    #("message", json.string(entry.message)),
  ])
}

// DECODING

/// Decodes a server event from JSON text.
pub fn decode_event(input: String) -> Result(ServerEvent, json.DecodeError) {
  json.parse(input, event_decoder())
}

/// Decodes a client command from JSON text.
pub fn decode_command(
  input: String,
) -> Result(ClientCommand, json.DecodeError) {
  json.parse(input, command_decoder())
}

/// Decoder for `ServerEvent`, keyed on the `type` field.
pub fn event_decoder() -> Decoder(ServerEvent) {
  use kind <- decode.field("type", decode.string)
  case kind {
    "snapshot" -> {
      use ship_name <- decode.field("ship_name", decode.string)
      use subsystems <- decode.field(
        "subsystems",
        decode.list(subsystem_decoder()),
      )
      use vm <- decode.field("vm", vm_decoder())
      use log <- decode.field("log", decode.list(log_entry_decoder()))
      decode.success(Snapshot(ship_name:, subsystems:, vm:, log:))
    }
    "subsystem_updated" -> {
      use subsystem <- decode.field("subsystem", subsystem_decoder())
      decode.success(SubsystemUpdated(subsystem))
    }
    "vm_updated" -> {
      use vm <- decode.field("vm", vm_decoder())
      decode.success(VmUpdated(vm))
    }
    "logged" -> {
      use entry <- decode.field("entry", log_entry_decoder())
      decode.success(Logged(entry))
    }
    _ -> decode.failure(VmUpdated(empty_vm()), "ServerEvent")
  }
}

/// Decoder for `ClientCommand`, keyed on the `type` field.
pub fn command_decoder() -> Decoder(ClientCommand) {
  use kind <- decode.field("type", decode.string)
  case kind {
    "inject_fault" -> {
      use id <- decode.field("id", subsystem_id_decoder())
      decode.success(InjectFault(id))
    }
    "reboot" -> {
      use id <- decode.field("id", subsystem_id_decoder())
      decode.success(Reboot(id))
    }
    "set_power" -> {
      use id <- decode.field("id", subsystem_id_decoder())
      use level <- decode.field("level", decode.int)
      decode.success(SetPower(id, level))
    }
    _ -> decode.failure(Reboot(Reactor), "ClientCommand")
  }
}

fn subsystem_id_decoder() -> Decoder(SubsystemId) {
  use name <- decode.then(decode.string)
  case name {
    "reactor" -> decode.success(Reactor)
    "shields" -> decode.success(Shields)
    "navigation" -> decode.success(Navigation)
    "comms" -> decode.success(Comms)
    "life_support" -> decode.success(LifeSupport)
    _ -> decode.failure(Reactor, "SubsystemId")
  }
}

fn status_decoder() -> Decoder(Status) {
  use kind <- decode.field("type", decode.string)
  case kind {
    "nominal" -> decode.success(Nominal)
    "degraded" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Degraded(reason:))
    }
    "offline" -> decode.success(Offline)
    "rebooting" -> decode.success(Rebooting)
    _ -> decode.failure(Offline, "Status")
  }
}

fn subsystem_decoder() -> Decoder(Subsystem) {
  use id <- decode.field("id", subsystem_id_decoder())
  use status <- decode.field("status", status_decoder())
  use power <- decode.field("power", decode.int)
  use load <- decode.field("load", decode.int)
  use temperature <- decode.field("temperature", decode.int)
  use restarts <- decode.field("restarts", decode.int)
  decode.success(Subsystem(id:, status:, power:, load:, temperature:, restarts:))
}

fn vm_decoder() -> Decoder(VmStats) {
  use process_count <- decode.field("process_count", decode.int)
  use memory_bytes <- decode.field("memory_bytes", decode.int)
  use run_queue <- decode.field("run_queue", decode.int)
  use schedulers <- decode.field("schedulers", decode.int)
  use uptime_ms <- decode.field("uptime_ms", decode.int)
  decode.success(VmStats(
    process_count:,
    memory_bytes:,
    run_queue:,
    schedulers:,
    uptime_ms:,
  ))
}

fn empty_vm() -> VmStats {
  VmStats(
    process_count: 0,
    memory_bytes: 0,
    run_queue: 0,
    schedulers: 0,
    uptime_ms: 0,
  )
}

fn severity_decoder() -> Decoder(Severity) {
  use name <- decode.then(decode.string)
  case name {
    "info" -> decode.success(Info)
    "warning" -> decode.success(Warning)
    "critical" -> decode.success(Critical)
    _ -> decode.failure(Info, "Severity")
  }
}

fn log_entry_decoder() -> Decoder(LogEntry) {
  use at_ms <- decode.field("at_ms", decode.int)
  use severity <- decode.field("severity", severity_decoder())
  use source <- decode.field("source", decode.string)
  use message <- decode.field("message", decode.string)
  decode.success(LogEntry(at_ms:, severity:, source:, message:))
}
