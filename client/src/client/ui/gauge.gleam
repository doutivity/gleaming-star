import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// Number of segments on the scale.
pub const segment_count = 20

/// Colour band of a reading.
pub type Level {
  Low
  Elevated
  Critical
}

/// `Low` below 60, `Elevated` below 85, `Critical` from 85.
pub fn level(value: Int) -> Level {
  case value {
    v if v >= 85 -> Critical
    v if v >= 60 -> Elevated
    _ -> Low
  }
}

/// CSS class for a level.
pub fn level_class(level: Level) -> String {
  case level {
    Low -> "level-low"
    Elevated -> "level-elevated"
    Critical -> "level-critical"
  }
}

/// How many of the 20 segments are lit for a 0..100 reading.
pub fn lit_segments(value: Int) -> Int {
  let clamped = int.clamp(value, 0, 100)
  { clamped * segment_count + 50 } / 100
}

/// A segmented scale with a label and a numeric readout.
pub fn view(label: String, value: Int, unit: String) -> Element(msg) {
  let lit = lit_segments(value)
  html.div(
    [
      attribute.class("gauge " <> level_class(level(value))),
      attribute.role("meter"),
      attribute.aria_label(label),
      attribute.attribute("aria-valuemin", "0"),
      attribute.attribute("aria-valuemax", "100"),
      attribute.attribute("aria-valuenow", int.to_string(value)),
      attribute.attribute("aria-valuetext", int.to_string(value) <> unit),
    ],
    [
      html.div([attribute.class("gauge__head")], [
        html.span([attribute.class("gauge__label")], [html.text(label)]),
        html.span([attribute.class("gauge__value")], [
          html.text(int.to_string(value) <> unit),
        ]),
      ]),
      html.div(
        [
          attribute.class("gauge__bar"),
          attribute.attribute("aria-hidden", "true"),
        ],
        segments(lit),
      ),
    ],
  )
}

fn segments(lit: Int) -> List(Element(msg)) {
  int.range(from: 0, to: segment_count, with: [], run: fn(acc, index) {
    let class = case index < lit {
      True -> "gauge__seg is-on"
      False -> "gauge__seg"
    }
    [html.span([attribute.class(class)], []), ..acc]
  })
  |> list.reverse
}
