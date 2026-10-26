import client/dashboard
import client/model.{Connecting, Lost, Online}
import shared/protocol.{
  Comms, Degraded, LifeSupport, Nominal, Offline, Reactor, Rebooting, Subsystem,
}

fn subsystem(status) {
  Subsystem(
    id: Reactor,
    status:,
    power: 50,
    load: 50,
    temperature: 50,
    restarts: 0,
  )
}

pub fn link_labels_test() {
  assert dashboard.link_label(Connecting) == "LINK CONNECTING"
  assert dashboard.link_label(Online) == "LINK ONLINE"
  assert dashboard.link_label(Lost) == "LINK LOST — RETRYING"
}

pub fn link_classes_are_distinct_test() {
  assert dashboard.link_class(Online) == "link--online"
  assert dashboard.link_class(Lost) == "link--lost"
  assert dashboard.link_class(Connecting) == "link--connecting"
}

pub fn status_labels_test() {
  assert dashboard.status_label(Nominal) == "NOMINAL"
  assert dashboard.status_label(Degraded("OVERHEAT")) == "DEGRADED (OVERHEAT)"
  assert dashboard.status_label(Offline) == "OFFLINE"
  assert dashboard.status_label(Rebooting) == "REBOOTING"
}

pub fn status_classes_test() {
  assert dashboard.status_class(Nominal) == "status--nominal"
  assert dashboard.status_class(Degraded("X")) == "status--degraded"
  assert dashboard.status_class(Offline) == "status--offline"
  assert dashboard.status_class(Rebooting) == "status--rebooting"
}

pub fn card_title_is_the_name_until_failure_test() {
  assert dashboard.card_title(subsystem(Nominal), False) == "REACTOR"
  assert dashboard.card_title(subsystem(Rebooting), True) == "SUBSYSTEM FAILURE"
  assert dashboard.card_title(subsystem(Offline), True) == "SUBSYSTEM FAILURE"
}

pub fn reboot_needs_a_link_and_a_running_subsystem_test() {
  assert dashboard.can_reboot(Online, Nominal)
  assert dashboard.can_reboot(Online, Degraded("OVERHEAT"))
  assert dashboard.can_reboot(Online, Rebooting) == False
  assert dashboard.can_reboot(Online, Offline) == False
  assert dashboard.can_reboot(Lost, Nominal) == False
  assert dashboard.can_reboot(Connecting, Nominal) == False
}

pub fn inject_fault_follows_the_same_rule_test() {
  assert dashboard.can_inject_fault(Online, Nominal)
  assert dashboard.can_inject_fault(Online, Rebooting) == False
  assert dashboard.can_inject_fault(Lost, Nominal) == False
}

pub fn power_can_be_set_while_rebooting_but_not_when_down_test() {
  assert dashboard.can_set_power(Online, Nominal)
  assert dashboard.can_set_power(Online, Rebooting)
  assert dashboard.can_set_power(Online, Offline) == False
  assert dashboard.can_set_power(Lost, Nominal) == False
}

pub fn alert_text_is_empty_without_failures_test() {
  assert dashboard.alert_text([]) == ""
}

pub fn alert_text_names_the_failed_subsystems_test() {
  assert dashboard.alert_text([Reactor]) == "SUBSYSTEM FAILURE: REACTOR"
  assert dashboard.alert_text([Comms, LifeSupport])
    == "SUBSYSTEM FAILURE: COMMS, LIFE SUPPORT"
}
