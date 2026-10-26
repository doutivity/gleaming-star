/// The ship's subsystems, each backed by its own OTP actor on the server.
pub type SubsystemId {
  Reactor
  Shields
  Navigation
  Comms
  LifeSupport
}

/// Every subsystem id, in display order.
pub const all_subsystems: List(SubsystemId) = [
  Reactor,
  Shields,
  Navigation,
  Comms,
  LifeSupport,
]

/// What a subsystem is doing right now.
pub type Status {
  Nominal
  Degraded(reason: String)
  Offline
  Rebooting
}

/// One subsystem's state as the server reports it.
pub type Subsystem {
  Subsystem(
    id: SubsystemId,
    status: Status,
    /// 0..100
    power: Int,
    /// 0..100
    load: Int,
    /// Degrees Celsius.
    temperature: Int,
    restarts: Int,
  )
}

/// Erlang VM metrics sampled by the server.
pub type VmStats {
  VmStats(
    process_count: Int,
    memory_bytes: Int,
    run_queue: Int,
    schedulers: Int,
    uptime_ms: Int,
  )
}

/// How serious a journal entry is.
pub type Severity {
  Info
  Warning
  Critical
}

/// One line of the event journal.
pub type LogEntry {
  LogEntry(at_ms: Int, severity: Severity, source: String, message: String)
}

/// Events streamed from the server to every client.
pub type ServerEvent {
  Snapshot(
    ship_name: String,
    subsystems: List(Subsystem),
    vm: VmStats,
    log: List(LogEntry),
  )
  SubsystemUpdated(Subsystem)
  VmUpdated(VmStats)
  Logged(LogEntry)
}

/// Commands sent from a client to the server.
pub type ClientCommand {
  InjectFault(SubsystemId)
  Reboot(SubsystemId)
  SetPower(SubsystemId, level: Int)
}

/// Upper-case display name of a subsystem, used in log sources and the UI.
pub fn subsystem_name(id: SubsystemId) -> String {
  case id {
    Reactor -> "REACTOR"
    Shields -> "SHIELDS"
    Navigation -> "NAVIGATION"
    Comms -> "COMMS"
    LifeSupport -> "LIFE SUPPORT"
  }
}
