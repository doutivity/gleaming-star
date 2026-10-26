import client/model.{type Model, type Msg}
import client/ui/animator.{type Anim, Entered, Entering, Exited, Exiting}
import client/ui/button
import client/ui/decipher
import client/ui/frame.{type Variant, Corners, Octagon, Underline}
import client/ui/gauge
import client/ui/log.{Line}
import client/ui/sparkline
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import shared/protocol.{Critical, Info, LogEntry, Warning}

/// The component showcase at `/#/kit`: every UI component in every state.
/// Panels enter one after another through the page `Stage`.
pub fn view(model: Model) -> Element(Msg) {
  let seed = model.frame / 3
  let title_anim = model.stage.parent
  html.main([attribute.class("kit")], [
    html.header([attribute.class("kit__header")], [
      html.h1([], [decipher.view("COMPONENT KIT", title_anim, seed)]),
      html.a([attribute.href("#/"), attribute.class("kit__back")], [
        html.text("← MISSION CONTROL"),
      ]),
    ]),
    html.div([attribute.class("kit__grid")], [
      controls(model, seed),
      frames(model, seed),
      buttons(model, seed),
      gauges(model, seed),
      sparklines(model, seed),
      deciphers(model, seed),
      journal(model, seed),
    ]),
  ])
}

fn panel(
  model: Model,
  index: Int,
  variant: Variant,
  title: String,
  content: List(Element(Msg)),
) -> Element(Msg) {
  let anim = animator.stage_child(model.stage, index)
  let seed = model.frame / 3
  frame.view(variant, danger: False, anim: anim, content: [
    html.h2([attribute.class("panel__title")], [
      decipher.view(title, anim, seed),
    ]),
    ..content
  ])
}

fn controls(model: Model, _seed: Int) -> Element(Msg) {
  let anim = animator.stage_child(model.stage, 0)
  panel(model, 0, Octagon, "ANIMATOR", [
    html.p([attribute.class("panel__note")], [
      html.text(
        "Page entrance: parent first, then panels 80 ms apart. State: "
        <> animator.state_name(model.stage.parent),
      ),
    ]),
    html.div([attribute.class("row")], [
      button.view(
        "REPLAY",
        "Replay page entrance",
        button.Primary,
        False,
        anim,
        model.KitReplay,
      ),
      button.view(
        "ENTER / EXIT",
        "Enter or exit all panels",
        button.Primary,
        False,
        anim,
        model.KitToggle,
      ),
    ]),
  ])
}

fn frames(model: Model, _seed: Int) -> Element(Msg) {
  let demo = fn(label: String, variant: Variant, danger: Bool, anim: Anim) {
    html.figure([attribute.class("demo")], [
      frame.view(variant, danger:, anim:, content: [
        html.div([attribute.class("demo__box")], []),
      ]),
      html.figcaption([attribute.class("demo__label")], [html.text(label)]),
    ])
  }
  panel(model, 1, Corners, "FRAMES", [
    html.div([attribute.class("demo-grid")], [
      demo("CORNERS · ENTERED", Corners, False, Entered),
      demo("OCTAGON · ENTERED", Octagon, False, Entered),
      demo("UNDERLINE · ENTERED", Underline, False, Entered),
      demo("OCTAGON · DANGER", Octagon, True, Entered),
      demo("EXITED", Octagon, False, Exited),
      demo("ENTERING 50%", Octagon, False, Entering(0.5)),
      demo("EXITING 50%", Octagon, False, Exiting(0.5)),
      demo("CORNERS · DANGER", Corners, True, Entered),
    ]),
  ])
}

fn buttons(model: Model, _seed: Int) -> Element(Msg) {
  let anim = animator.stage_child(model.stage, 2)
  panel(model, 2, Corners, "BUTTONS", [
    html.div([attribute.class("row")], [
      button.view(
        "REBOOT",
        "Reboot (enabled sample)",
        button.Primary,
        False,
        anim,
        model.Noop,
      ),
      button.view(
        "REBOOT",
        "Reboot (disabled sample)",
        button.Primary,
        True,
        anim,
        model.Noop,
      ),
      button.view(
        "INJECT FAULT",
        "Inject fault (enabled sample)",
        button.Danger,
        False,
        anim,
        model.Noop,
      ),
      button.view(
        "INJECT FAULT",
        "Inject fault (disabled sample)",
        button.Danger,
        True,
        anim,
        model.Noop,
      ),
    ]),
  ])
}

fn gauges(model: Model, _seed: Int) -> Element(Msg) {
  panel(model, 3, Corners, "GAUGES", [
    gauge.view("EMPTY", 0, "%"),
    gauge.view("LOW", 28, "%"),
    gauge.view("ELEVATED", 72, "%"),
    gauge.view("CRITICAL", 91, "%"),
    gauge.view("FULL", 100, "%"),
  ])
}

fn sparklines(model: Model, _seed: Int) -> Element(Msg) {
  let wave =
    int.range(from: 0, to: 70, with: [], run: fn(acc, i) {
      [50 + { i * 7 } % 23 + i / 3, ..acc]
    })
    |> list.reverse
  panel(model, 4, Corners, "SPARKLINES", [
    sparkline.view("RISING NOISE", wave, "latest " <> latest(wave)),
    sparkline.view("FLAT", [10, 10, 10, 10], "10"),
    sparkline.view("SINGLE POINT", [42], "42"),
    sparkline.view("EMPTY", [], "—"),
  ])
}

fn latest(values: List(Int)) -> String {
  case list.last(values) {
    Ok(value) -> int.to_string(value)
    Error(Nil) -> "—"
  }
}

fn deciphers(model: Model, seed: Int) -> Element(Msg) {
  let text = "SUBSYSTEM FAILURE — REROUTING POWER"
  let live = animator.lookup(model.anims, "kit-decipher")
  let static = fn(p: Float) {
    html.p([attribute.class("decipher-sample")], [
      html.text(decipher.render(text, p, 7)),
    ])
  }
  panel(model, 5, Corners, "DECIPHER", [
    static(0.0),
    static(0.4),
    static(1.0),
    html.p([attribute.class("decipher-sample")], [
      decipher.view(text, live, seed),
    ]),
    html.div([attribute.class("row")], [
      button.view(
        "REPLAY TEXT",
        "Replay the decipher sample",
        button.Primary,
        False,
        animator.stage_child(model.stage, 5),
        model.KitDecipher,
      ),
    ]),
  ])
}

fn journal(model: Model, seed: Int) -> Element(Msg) {
  let starter = [
    Line(-3, LogEntry(0, Info, "REACTOR", "ONLINE — ALL CHECKS PASSED")),
    Line(-2, LogEntry(0, Warning, "SHIELDS", "OVERHEAT DETECTED")),
    Line(-1, LogEntry(0, Critical, "COMMS", "SUBSYSTEM FAILURE")),
  ]
  panel(model, 6, Corners, "LOG", [
    log.view(list.append(starter, model.kit_log), model.anims, seed),
    html.div([attribute.class("row")], [
      button.view(
        "ADD LINE",
        "Add a line to the sample log",
        button.Primary,
        False,
        animator.stage_child(model.stage, 6),
        model.KitAddLine,
      ),
    ]),
  ])
}
