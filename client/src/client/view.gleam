import client/dashboard
import client/kit
import client/model.{type Model, type Msg}
import client/route.{Dashboard, Kit}
import client/ui/background
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// The whole page: backdrop plus the current route.
pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("app")], [
    background.view(),
    case model.route {
      Dashboard -> dashboard.view(model)
      Kit -> kit.view(model)
    },
  ])
}
