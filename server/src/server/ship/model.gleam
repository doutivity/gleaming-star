import gleam/int
import gleam/option.{type Option, None, Some}
import shared/protocol.{
  type Severity, type Subsystem, type SubsystemId, Comms, Critical, Degraded,
  Info, LifeSupport, Navigation, Nominal, Reactor, Rebooting, Shields, Subsystem,
  Warning,
}

/// Temperature at which a running subsystem becomes `Degraded`.
pub const overheat_at = 82

/// Temperature at which a degraded subsystem recovers to `Nominal`.
pub const recover_at = 72

const overheat_reason = "OVERHEAT"

/// A freshly started subsystem: `Rebooting`, with typical power for its role.
pub fn initial(id: SubsystemId, restarts: Int) -> Subsystem {
  Subsystem(
    id:,
    status: Rebooting,
    power: default_power(id),
    load: 10,
    temperature: 35,
    restarts:,
  )
}

fn default_power(id: SubsystemId) -> Int {
  case id {
    Reactor -> 90
    Shields -> 70
    Navigation -> 60
    Comms -> 65
    LifeSupport -> 85
  }
}

/// Clamps to the 0..100 range used by power and load.
pub fn clamp_percent(value: Int) -> Int {
  int.clamp(value, 0, 100)
}

/// One simulation step. `load_delta` and `noise` are random inputs chosen by
/// the caller, which keeps this function pure. Only running subsystems drift.
pub fn drift(subsystem: Subsystem, load_delta: Int, noise: Int) -> Subsystem {
  case subsystem.status {
    Nominal | Degraded(_) -> {
      // Mean reversion keeps load wandering around 50 instead of saturating.
      let load =
        int.clamp(
          subsystem.load + load_delta + { 50 - subsystem.load } / 10,
          5,
          95,
        )
      let target = 30 + load * 6 / 10 + { subsystem.power - 50 } / 4
      let step = int.clamp(target - subsystem.temperature, -2, 2)
      let temperature = subsystem.temperature + step + noise
      Subsystem(
        ..subsystem,
        load:,
        temperature:,
        status: thermal_status(subsystem.status, temperature),
      )
    }
    _ -> subsystem
  }
}

/// Applies hysteresis: overheat above `overheat_at`, recover below `recover_at`.
fn thermal_status(current, temperature: Int) {
  case current {
    Nominal if temperature >= overheat_at -> Degraded(overheat_reason)
    Degraded(_) if temperature <= recover_at -> Nominal
    other -> other
  }
}

/// Sets power, clamped to 0..100.
pub fn set_power(subsystem: Subsystem, level: Int) -> Subsystem {
  Subsystem(..subsystem, power: clamp_percent(level))
}

/// Starts a controlled reboot: load drops, the core cools a little.
pub fn reboot(subsystem: Subsystem) -> Subsystem {
  Subsystem(
    ..subsystem,
    status: Rebooting,
    load: 10,
    temperature: int.max(35, subsystem.temperature - 15),
  )
}

/// Finishes a reboot. Does nothing unless the subsystem is `Rebooting`.
pub fn boot_complete(subsystem: Subsystem) -> Subsystem {
  case subsystem.status {
    Rebooting -> Subsystem(..subsystem, status: Nominal)
    _ -> subsystem
  }
}

/// The journal entry (if any) describing a status change.
pub fn transition_log(
  before: Subsystem,
  after: Subsystem,
) -> Option(#(Severity, String)) {
  case before.status, after.status {
    Nominal, Degraded(reason) -> Some(#(Warning, reason <> " DETECTED"))
    Degraded(_), Nominal -> Some(#(Info, "THERMAL LEVELS NOMINAL"))
    Rebooting, Nominal -> Some(#(Info, "ONLINE — ALL CHECKS PASSED"))
    _, _ -> None
  }
}

/// Journal text for a subsystem that has just crashed.
pub fn failure_log() -> #(Severity, String) {
  #(Critical, "SUBSYSTEM FAILURE — SUPERVISOR REROUTING")
}
