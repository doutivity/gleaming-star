import client/format
import client/model.{
  type Link, type Model, type Msg, Connecting, Lost, Online, PowerChanged,
}
import client/ui/animator.{Entered}
import client/ui/button
import client/ui/decipher
import client/ui/frame
import client/ui/gauge
import client/ui/log
import client/ui/sparkline
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared/protocol.{
  type Status, type Subsystem, type SubsystemId, type VmStats, Degraded,
  InjectFault, Nominal, Offline, Reboot, Rebooting,
}

/// The title shown for a ship's name before the server has told us.
const default_title = "MISSION CONTROL"

const failure_title = "SUBSYSTEM FAILURE"

/// Index of the telemetry panel among the stage's children; subsystem cards
/// use their position in `protocol.all_subsystems`, and the log comes last.
const telemetry_panel = 5

const log_panel = 6

// RULES (pure, so they can be tested without a DOM)

/// Text for the connection indicator.
pub fn link_label(link: Link) -> String {
  case link {
    Connecting -> "LINK CONNECTING"
    Online -> "LINK ONLINE"
    Lost -> "LINK LOST — RETRYING"
  }
}

/// CSS class for the connection indicator.
pub fn link_class(link: Link) -> String {
  case link {
    Connecting -> "link--connecting"
    Online -> "link--online"
    Lost -> "link--lost"
  }
}

/// Text for a subsystem status.
pub fn status_label(status: Status) -> String {
  case status {
    Nominal -> "NOMINAL"
    Degraded(reason) -> "DEGRADED (" <> reason <> ")"
    Offline -> "OFFLINE"
    Rebooting -> "REBOOTING"
  }
}

/// CSS class for a subsystem status.
pub fn status_class(status: Status) -> String {
  case status {
    Nominal -> "status--nominal"
    Degraded(_) -> "status--degraded"
    Offline -> "status--offline"
    Rebooting -> "status--rebooting"
  }
}

/// A card's heading: the subsystem's name, or the alarm while it is failed.
pub fn card_title(subsystem: Subsystem, failed: Bool) -> String {
  case failed {
    True -> failure_title
    False -> protocol.subsystem_name(subsystem.id)
  }
}

/// What assistive technology announces when subsystems fail; empty when none
/// has.
pub fn alert_text(failed: List(SubsystemId)) -> String {
  case failed {
    [] -> ""
    ids ->
      "SUBSYSTEM FAILURE: "
      <> string.join(list.map(ids, protocol.subsystem_name), ", ")
  }
}

/// A subsystem that is neither rebooting nor down can be rebooted by hand.
pub fn can_reboot(link: Link, status: Status) -> Bool {
  link == Online && status != Rebooting && status != Offline
}

/// Same rule for injecting a fault: nothing to break while it is down.
pub fn can_inject_fault(link: Link, status: Status) -> Bool {
  can_reboot(link, status)
}

/// Power can be set whenever the subsystem is not down.
pub fn can_set_power(link: Link, status: Status) -> Bool {
  link == Online && status != Offline
}

// VIEW

/// The dashboard: header, subsystem cards, VM telemetry and the journal.
pub fn view(model: Model) -> Element(Msg) {
  let seed = model.frame / 3
  html.main([attribute.class("dash")], [
    alerts(model),
    header(model, seed),
    html.div([attribute.class("dash__grid")], [
      html.section(
        [attribute.class("dash__ships"), attribute.aria_label("Subsystems")],
        list.map(model.ordered_subsystems(model), fn(subsystem) {
          card(model, subsystem, seed)
        }),
      ),
      telemetry(model, seed),
      journal(model, seed),
    ]),
    html.footer([attribute.class("dash__footer")], [
      html.a([attribute.href("#/kit")], [html.text("COMPONENT KIT")]),
    ]),
  ])
}

/// A live region screen readers announce at once when it changes. Always in
/// the page, so that the first failure is announced too.
fn alerts(model: Model) -> Element(Msg) {
  let failed = list.filter(protocol.all_subsystems, model.is_failed(model, _))
  html.div([attribute.class("sr-only"), attribute.role("alert")], [
    html.text(alert_text(failed)),
  ])
}

fn header(model: Model, seed: Int) -> Element(Msg) {
  let title = case model.ship_name {
    "" -> default_title
    name -> name
  }
  // The name is deciphered when it first arrives; before that, and once it
  // has settled, the page entrance drives it.
  let anim = case animator.lookup(model.anims, model.ship_name_key) {
    Entered -> model.stage.parent
    running -> running
  }
  frame.view(frame.Underline, danger: False, anim: model.stage.parent, content: [
    html.div([attribute.class("header")], [
      html.h1([attribute.class("header__title")], [
        decipher.view(title, anim, seed),
      ]),
      html.span([attribute.class("header__clock")], [
        html.text(format.utc_clock(model.now_ms) <> " UTC"),
      ]),
      html.span(
        [
          attribute.class("link " <> link_class(model.link)),
          attribute.role("status"),
        ],
        [html.text(link_label(model.link))],
      ),
    ]),
  ])
}

fn card(model: Model, subsystem: Subsystem, seed: Int) -> Element(Msg) {
  let failed = model.is_failed(model, subsystem.id)
  let name = protocol.subsystem_name(subsystem.id)
  let panel_anim = animator.stage_child(model.stage, index_of(subsystem.id))
  let title_anim = case
    animator.lookup(model.anims, model.title_key(subsystem.id))
  {
    Entered -> panel_anim
    running -> running
  }
  frame.view(frame.Octagon, danger: failed, anim: panel_anim, content: [
    html.article([attribute.class("card"), attribute.aria_label(name)], [
      html.h2([attribute.class("panel__title")], [
        decipher.view(card_title(subsystem, failed), title_anim, seed),
      ]),
      html.p(
        [
          attribute.class("card__status " <> status_class(subsystem.status)),
          attribute.attribute("aria-live", "polite"),
        ],
        [html.text(status_label(subsystem.status))],
      ),
      gauge.view("POWER", subsystem.power, "%"),
      gauge.view("LOAD", subsystem.load, "%"),
      gauge.view("TEMP", subsystem.temperature, "°C"),
      html.p([attribute.class("card__meta")], [
        html.text("RESTARTS " <> int.to_string(subsystem.restarts)),
      ]),
      slider(model, subsystem, name),
      html.div([attribute.class("row")], [
        button.view(
          "REBOOT",
          "Reboot " <> name,
          button.Primary,
          !can_reboot(model.link, subsystem.status),
          panel_anim,
          model.Operate(Reboot(subsystem.id)),
        ),
        button.view(
          "INJECT FAULT",
          "Inject fault into " <> name,
          button.Danger,
          !can_inject_fault(model.link, subsystem.status),
          panel_anim,
          model.Operate(InjectFault(subsystem.id)),
        ),
      ]),
    ]),
  ])
}

fn slider(model: Model, subsystem: Subsystem, name: String) -> Element(Msg) {
  html.label([attribute.class("slider")], [
    html.span([attribute.class("slider__label")], [html.text("POWER LEVEL")]),
    html.input([
      attribute.class("slider__input"),
      attribute.type_("range"),
      attribute.min("0"),
      attribute.max("100"),
      attribute.step("5"),
      attribute.value(int.to_string(subsystem.power)),
      attribute.disabled(!can_set_power(model.link, subsystem.status)),
      attribute.aria_label(name <> " power level"),
      event.on_change(fn(value) { PowerChanged(subsystem.id, value) }),
    ]),
  ])
}

fn index_of(id: SubsystemId) -> Int {
  protocol.all_subsystems
  |> list.index_map(fn(candidate, index) { #(candidate, index) })
  |> list.key_find(id)
  |> option.from_result
  |> option.unwrap(0)
}

fn telemetry(model: Model, seed: Int) -> Element(Msg) {
  let anim = animator.stage_child(model.stage, telemetry_panel)
  frame.view(frame.Corners, danger: False, anim:, content: [
    html.h2([attribute.class("panel__title")], [
      decipher.view("VM TELEMETRY", anim, seed),
    ]),
    case model.vm {
      None ->
        html.p([attribute.class("panel__note")], [
          html.text("AWAITING TELEMETRY"),
        ])
      Some(vm) ->
        html.div([], [
          stats(vm),
          sparkline.view(
            "MEMORY",
            model.memory_history,
            format.memory(vm.memory_bytes),
          ),
          sparkline.view(
            "PROCESSES",
            model.process_history,
            int.to_string(vm.process_count),
          ),
        ])
    },
  ])
}

fn stats(vm: VmStats) -> Element(Msg) {
  html.dl([attribute.class("stats")], [
    stat("PROCESSES", int.to_string(vm.process_count)),
    stat("MEMORY", format.memory(vm.memory_bytes)),
    stat("RUN QUEUE", int.to_string(vm.run_queue)),
    stat("SCHEDULERS", int.to_string(vm.schedulers)),
    stat("UPTIME", format.uptime(vm.uptime_ms)),
  ])
}

fn stat(label: String, value: String) -> Element(Msg) {
  html.div([attribute.class("stat")], [
    html.dt([attribute.class("stat__label")], [html.text(label)]),
    html.dd([attribute.class("stat__value")], [html.text(value)]),
  ])
}

fn journal(model: Model, seed: Int) -> Element(Msg) {
  let anim = animator.stage_child(model.stage, log_panel)
  frame.view(frame.Corners, danger: False, anim:, content: [
    html.h2([attribute.class("panel__title")], [
      decipher.view("EVENT LOG", anim, seed),
    ]),
    html.div([attribute.class("dash__log")], [
      log.view(model.log, model.anims, seed),
    ]),
  ])
}
