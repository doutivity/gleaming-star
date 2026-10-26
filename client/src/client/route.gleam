import gleam/string

/// Pages of the single-page app.
pub type Route {
  Dashboard
  /// The component showcase at `/#/kit`.
  Kit
}

/// Reads a URL hash, with or without the leading `#`: `plinth` gives it
/// without, `window.location.hash` with. Anything unknown is the dashboard.
pub fn parse(hash: String) -> Route {
  case string.remove_prefix(hash, "#") {
    "/kit" | "/kit/" -> Kit
    _ -> Dashboard
  }
}
