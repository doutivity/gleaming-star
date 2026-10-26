import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/option.{Some}
import mist.{type Connection, type ResponseData}
import server/hub
import server/names.{type Names}
import server/ship/subsystem
import shared/codec
import shared/protocol.{type ServerEvent}

/// Upgrades the request to a WebSocket. The connection subscribes to the hub
/// (which replies with a `Snapshot`), forwards every event as JSON text, and
/// turns incoming JSON into commands for subsystems. Bad input is logged and
/// ignored; the connection stays up.
pub fn upgrade(
  req: Request(Connection),
  names: Names,
) -> Response(ResponseData) {
  let hub = names.hub_subject(names)
  mist.websocket(
    request: req,
    on_init: fn(_connection) {
      let events = process.new_subject()
      process.send(hub, hub.Subscribe(events))
      #(events, Some(process.new_selector() |> process.select(events)))
    },
    handler: fn(events, message, connection) {
      handle_message(names, events, message, connection)
    },
    on_close: fn(events) { process.send(hub, hub.Unsubscribe(events)) },
  )
}

fn handle_message(
  names: Names,
  events: Subject(ServerEvent),
  message: mist.WebsocketMessage(ServerEvent),
  connection: mist.WebsocketConnection,
) -> mist.Next(Subject(ServerEvent), ServerEvent) {
  case message {
    mist.Custom(event) ->
      case mist.send_text_frame(connection, codec.encode_event(event)) {
        Ok(Nil) -> mist.continue(events)
        Error(_) -> mist.stop()
      }
    mist.Text(text) -> {
      handle_text(names, text)
      mist.continue(events)
    }
    mist.Binary(_) -> mist.continue(events)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn handle_text(names: Names, text: String) -> Nil {
  case codec.decode_command(text) {
    Ok(command) -> {
      let #(id, message) = subsystem.route_command(command)
      case names.send_to_subsystem(names, id, message) {
        Ok(Nil) -> Nil
        Error(Nil) ->
          io.println_error(
            "ws: "
            <> protocol.subsystem_name(id)
            <> " is not running, command dropped",
          )
      }
    }
    Error(_) -> io.println_error("ws: ignoring invalid command: " <> text)
  }
}
