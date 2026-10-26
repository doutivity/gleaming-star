import gleam/option.{None, Some}
import server/ship/model
import shared/protocol.{
  type Subsystem, Critical, Degraded, Info, Nominal, Offline, Reactor, Rebooting,
  Subsystem, Warning,
}

fn running(load load: Int, temperature temperature: Int) -> Subsystem {
  Subsystem(
    id: Reactor,
    status: Nominal,
    power: 50,
    load:,
    temperature:,
    restarts: 0,
  )
}

pub fn initial_is_rebooting_test() {
  let subsystem = model.initial(Reactor, 3)
  assert subsystem.status == Rebooting
  assert subsystem.restarts == 3
}

pub fn drift_ignores_non_running_test() {
  let rebooting = Subsystem(..running(50, 50), status: Rebooting)
  let offline = Subsystem(..running(50, 50), status: Offline)
  assert model.drift(rebooting, 5, 1) == rebooting
  assert model.drift(offline, 5, 1) == offline
}

pub fn drift_clamps_load_test() {
  assert model.drift(running(95, 60), 10, 0).load == 95
  assert model.drift(running(5, 60), -10, 0).load == 5
}

pub fn drift_pulls_load_towards_middle_test() {
  assert model.drift(running(90, 60), 0, 0).load == 86
  assert model.drift(running(10, 60), 0, 0).load == 14
}

pub fn drift_moves_temperature_towards_target_test() {
  // load 50 and power 50 give a target of 60 degrees; steps are at most 2.
  assert model.drift(running(50, 40), 0, 0).temperature == 42
  assert model.drift(running(50, 70), 0, 0).temperature == 68
  assert model.drift(running(50, 61), 0, 0).temperature == 60
}

pub fn overheat_degrades_test() {
  assert model.drift(running(50, 86), 0, 0).status == Degraded("OVERHEAT")
}

pub fn recovery_has_hysteresis_test() {
  let degraded = Subsystem(..running(50, 76), status: Degraded("OVERHEAT"))
  // 76 -> 74: still above the recovery threshold.
  assert model.drift(degraded, 0, 0).status == Degraded("OVERHEAT")
  // 74 -> 72: recovered.
  let cooler = Subsystem(..degraded, temperature: 74)
  assert model.drift(cooler, 0, 0).status == Nominal
}

pub fn set_power_clamps_test() {
  assert model.set_power(running(50, 50), 140).power == 100
  assert model.set_power(running(50, 50), -3).power == 0
  assert model.set_power(running(50, 50), 42).power == 42
}

pub fn reboot_then_boot_complete_test() {
  let rebooted = model.reboot(running(80, 70))
  assert rebooted.status == Rebooting
  assert rebooted.load == 10
  assert rebooted.temperature == 55
  assert model.boot_complete(rebooted).status == Nominal
}

pub fn reboot_keeps_a_cool_floor_test() {
  assert model.reboot(running(80, 40)).temperature == 35
}

pub fn boot_complete_only_affects_rebooting_test() {
  let degraded = Subsystem(..running(50, 80), status: Degraded("OVERHEAT"))
  assert model.boot_complete(degraded) == degraded
}

pub fn transition_log_test() {
  let nominal = running(50, 50)
  let degraded = Subsystem(..nominal, status: Degraded("OVERHEAT"))
  let rebooting = Subsystem(..nominal, status: Rebooting)
  assert model.transition_log(nominal, degraded)
    == Some(#(Warning, "OVERHEAT DETECTED"))
  assert model.transition_log(degraded, nominal)
    == Some(#(Info, "THERMAL LEVELS NOMINAL"))
  assert model.transition_log(rebooting, nominal)
    == Some(#(Info, "ONLINE — ALL CHECKS PASSED"))
  assert model.transition_log(nominal, nominal) == None
  assert model.failure_log().0 == Critical
}
