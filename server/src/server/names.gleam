import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import server/hub
import server/ship/subsystem
import shared/protocol.{type SubsystemId}

/// Registered names of the long-lived processes. Names stay valid across
/// supervisor restarts, so nobody has to hold on to a pid or a subject.
/// Create once at startup: every call to `new` makes fresh names.
pub type Names {
  Names(
    hub: Name(hub.Message),
    subsystems: List(#(SubsystemId, Name(subsystem.Message))),
  )
}

/// Creates a fresh set of names.
pub fn new() -> Names {
  Names(
    hub: process.new_name("hub"),
    subsystems: list.map(protocol.all_subsystems, fn(id) {
      #(id, process.new_name("subsystem"))
    }),
  )
}

/// The hub's address.
pub fn hub_subject(names: Names) -> Subject(hub.Message) {
  process.named_subject(names.hub)
}

/// Delivers a message to a subsystem. `Error` means the subsystem is not
/// running right now (for example, mid-restart); the message is dropped.
pub fn send_to_subsystem(
  names: Names,
  id: SubsystemId,
  message: subsystem.Message,
) -> Result(Nil, Nil) {
  case list.key_find(names.subsystems, id) {
    Ok(name) ->
      case process.named(name) {
        Ok(_) -> Ok(process.send(process.named_subject(name), message))
        Error(Nil) -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}
