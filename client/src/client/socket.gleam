import client/model.{type Msg, Reconnect, Socket}
import gleam/int
import lustre/effect.{type Effect}
import lustre_websocket.{type WebSocket}
import plinth/javascript/global
import shared/codec
import shared/protocol.{type ClientCommand}

const first_delay_ms = 500

const max_delay_ms = 10_000

/// Delay before reconnect attempt number `attempts` (0-based): 0.5 s, 1 s,
/// 2 s, 4 s, 8 s, then 10 s at most.
pub fn backoff_ms(attempts: Int) -> Int {
  // Past 5 doublings the cap applies anyway; this also avoids huge shifts.
  let doublings = int.min(attempts, 5)
  int.min(first_delay_ms * int.bitwise_shift_left(1, doublings), max_delay_ms)
}

/// Opens the WebSocket to the server that served this page.
pub fn connect() -> Effect(Msg) {
  lustre_websocket.init("/ws", Socket)
}

/// Asks for a `Reconnect` message once the backoff for `attempts` has passed.
pub fn reconnect_after(attempts: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    global.set_timeout(backoff_ms(attempts), fn() { dispatch(Reconnect) })
    Nil
  })
}

/// Sends a command to the server as JSON text.
pub fn send(ws: WebSocket, command: ClientCommand) -> Effect(Msg) {
  lustre_websocket.send(ws, codec.encode_command(command))
}
