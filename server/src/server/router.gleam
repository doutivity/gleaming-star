import gleam/bytes_tree
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None}
import gleam/string
import mist.{type Connection, type ResponseData}
import server/names.{type Names}
import server/ws

/// Where a request is going, decided purely from method and path.
pub type Route {
  Index
  Health
  Ws
  Static(path: List(String))
  NotFound
}

/// Maps an HTTP method and path segments to a `Route`.
/// Static paths containing traversal-looking segments are rejected.
pub fn route(method: http.Method, segments: List(String)) -> Route {
  case method, segments {
    http.Get, [] -> Index
    http.Get, ["health"] -> Health
    http.Get, ["ws"] -> Ws
    http.Get, ["static", ..rest] if rest != [] ->
      case list.all(rest, is_safe_segment) {
        True -> Static(rest)
        False -> NotFound
      }
    _, _ -> NotFound
  }
}

fn is_safe_segment(segment: String) -> Bool {
  segment != ""
  && !string.starts_with(segment, ".")
  && !string.contains(segment, "/")
  && !string.contains(segment, "\\")
}

/// Content-Type for a file name, based on its extension.
pub fn content_type(file_name: String) -> String {
  case string.split(file_name, ".") |> list.last {
    Ok("html") -> "text/html; charset=utf-8"
    Ok("css") -> "text/css; charset=utf-8"
    Ok("js") | Ok("mjs") -> "text/javascript; charset=utf-8"
    Ok("json") -> "application/json; charset=utf-8"
    Ok("svg") -> "image/svg+xml"
    Ok("png") -> "image/png"
    Ok("ico") -> "image/x-icon"
    Ok("woff2") -> "font/woff2"
    _ -> "application/octet-stream"
  }
}

/// Handles one HTTP request. `priv` is the application's `priv` directory.
/// `names` addresses the OTP processes that `/ws` talks to.
pub fn handle(
  req: Request(Connection),
  priv: String,
  names: Names,
) -> Response(ResponseData) {
  case route(req.method, request.path_segments(req)) {
    Index -> file_response(priv <> "/static/index.html")
    Health -> text_response(200, "ok")
    Ws -> ws.upgrade(req, names)
    Static(path) -> file_response(priv <> "/static/" <> string.join(path, "/"))
    NotFound -> text_response(404, "not found")
  }
}

fn file_response(path: String) -> Response(ResponseData) {
  case mist.send_file(path, offset: 0, limit: None) {
    Ok(body) ->
      response.new(200)
      |> response.set_header("content-type", content_type(path))
      |> response.set_body(body)
    Error(_) -> text_response(404, "not found")
  }
}

fn text_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}
