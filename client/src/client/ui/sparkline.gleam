import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/svg

/// The sparkline shows at most this many of the latest points.
pub const max_points = 60

const width = 120

const height = 32

const padding = 2.0

/// The `points` attribute of the polyline: the last `max_points` values
/// scaled to a `width` x `height` box, newest on the right. Higher values are
/// drawn higher up. A flat series is drawn as a line through the middle.
pub fn points(values: List(Int)) -> String {
  let values = list.drop(values, list.length(values) - max_points)
  case values {
    [] -> ""
    [only] -> points([only, only])
    _ -> {
      let low = list.fold(values, list.first(values) |> unwrap(0), int.min)
      let high = list.fold(values, low, int.max)
      let count = list.length(values)
      values
      |> list.index_map(fn(value, index) {
        let x =
          int.to_float(index) *. int.to_float(width) /. int.to_float(count - 1)
        let y = case high == low {
          True -> int.to_float(height) /. 2.0
          False -> {
            let usable = int.to_float(height) -. 2.0 *. padding
            let ratio = int.to_float(value - low) /. int.to_float(high - low)
            int.to_float(height) -. padding -. ratio *. usable
          }
        }
        format(x) <> "," <> format(y)
      })
      |> string.join(" ")
    }
  }
}

fn unwrap(result: Result(Int, Nil), default: Int) -> Int {
  case result {
    Ok(value) -> value
    Error(Nil) -> default
  }
}

/// One decimal place, enough for a 120 px wide chart.
fn format(value: Float) -> String {
  float.to_string(int.to_float(float.round(value *. 10.0)) /. 10.0)
}

/// An inline SVG line chart with a caption and the latest value.
pub fn view(label: String, values: List(Int), latest: String) -> Element(msg) {
  element.element("figure", [attribute.class("sparkline")], [
    element.element("figcaption", [attribute.class("sparkline__head")], [
      element.element("span", [], [element.text(label)]),
      element.element("strong", [], [element.text(latest)]),
    ]),
    svg.svg(
      [
        attribute.class("sparkline__svg"),
        attribute.attribute(
          "viewBox",
          "0 0 " <> int.to_string(width) <> " " <> int.to_string(height),
        ),
        attribute.attribute("preserveAspectRatio", "none"),
        attribute.role("img"),
        attribute.aria_label(label <> " history"),
      ],
      [
        svg.polyline([
          attribute.class("sparkline__line"),
          attribute.attribute("points", points(values)),
          attribute.attribute("fill", "none"),
          attribute.attribute("vector-effect", "non-scaling-stroke"),
        ]),
      ],
    ),
  ])
}
