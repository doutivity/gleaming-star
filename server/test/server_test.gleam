import gleam/http
import gleeunit
import server/router.{Health, Index, NotFound, Static, Ws}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn route_index_test() {
  assert router.route(http.Get, []) == Index
}

pub fn route_health_test() {
  assert router.route(http.Get, ["health"]) == Health
}

pub fn route_ws_test() {
  assert router.route(http.Get, ["ws"]) == Ws
  assert router.route(http.Post, ["ws"]) == NotFound
}

pub fn route_static_test() {
  assert router.route(http.Get, ["static", "styles.css"])
    == Static(["styles.css"])
  assert router.route(http.Get, ["static", "fonts", "a.woff2"])
    == Static(["fonts", "a.woff2"])
}

pub fn route_rejects_traversal_test() {
  assert router.route(http.Get, ["static", "..", "secret"]) == NotFound
  assert router.route(http.Get, ["static", ".hidden"]) == NotFound
  assert router.route(http.Get, ["static", "a\\b"]) == NotFound
}

pub fn route_unknown_test() {
  assert router.route(http.Get, ["static"]) == NotFound
  assert router.route(http.Get, ["nope"]) == NotFound
  assert router.route(http.Post, ["health"]) == NotFound
}

pub fn content_type_test() {
  assert router.content_type("a/index.html") == "text/html; charset=utf-8"
  assert router.content_type("styles.css") == "text/css; charset=utf-8"
  assert router.content_type("unknown.bin") == "application/octet-stream"
  assert router.content_type("noext") == "application/octet-stream"
}
