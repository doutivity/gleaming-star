import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// The page backdrop: grid, dot matrix, a slow scan line and a vignette. All
/// of it is CSS; there is no scripted animation.
pub fn view() -> Element(msg) {
  html.div([attribute.class("bg"), attribute.attribute("aria-hidden", "true")], [
    html.div([attribute.class("bg__grid")], []),
    html.div([attribute.class("bg__dots")], []),
    html.div([attribute.class("bg__scan")], []),
    html.div([attribute.class("bg__vignette")], []),
  ])
}
