import client/ui/animator.{type Registry}
import client/ui/decipher
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import shared/protocol.{type LogEntry, type Severity, Critical, Info, Warning}

/// A journal entry with a stable id, which keys its decipher animation.
pub type Line {
  Line(id: Int, entry: LogEntry)
}

/// Key of the animation of line `id` in the animation registry.
pub fn anim_key(id: Int) -> String {
  "log-" <> int.to_string(id)
}

/// CSS class for a severity.
pub fn severity_class(severity: Severity) -> String {
  case severity {
    Info -> "sev-info"
    Warning -> "sev-warning"
    Critical -> "sev-critical"
  }
}

/// Short tag shown before the message.
pub fn severity_tag(severity: Severity) -> String {
  case severity {
    Info -> "INFO"
    Warning -> "WARN"
    Critical -> "CRIT"
  }
}

/// The text of one line.
pub fn line_text(entry: LogEntry) -> String {
  "["
  <> severity_tag(entry.severity)
  <> "] "
  <> entry.source
  <> ": "
  <> entry.message
}

/// A terminal-style journal. `lines` is oldest first. The DOM holds the
/// newest line first and the container is a reversed flex column, so it stays
/// pinned to the bottom, with the newest line there, without any scripting.
/// `aria-live="polite"` announces new lines.
pub fn view(lines: List(Line), anims: Registry, seed: Int) -> Element(msg) {
  html.ol(
    [
      attribute.class("log"),
      attribute.attribute("aria-live", "polite"),
      attribute.attribute("aria-relevant", "additions"),
      attribute.role("log"),
      // A scrollable region must be reachable from the keyboard.
      attribute.attribute("tabindex", "0"),
      attribute.aria_label("Event log"),
    ],
    lines
      |> list.reverse
      |> list.map(fn(line) {
        html.li(
          [
            attribute.class("log__line " <> severity_class(line.entry.severity)),
          ],
          [
            decipher.view(
              line_text(line.entry),
              animator.lookup(anims, anim_key(line.id)),
              seed,
            ),
          ],
        )
      }),
  )
}
