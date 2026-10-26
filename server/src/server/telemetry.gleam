import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision
import server/hub
import server/vm
import shared/protocol.{VmUpdated}

const interval_ms = 1000

/// The only message: sample the VM now.
pub type Tick {
  Tick
}

/// Publishes a `VmUpdated` event once per second, starting immediately.
pub fn start(hub: Subject(hub.Message)) -> actor.StartResult(Subject(Tick)) {
  actor.new_with_initialiser(1000, fn(self) {
    process.send(self, Tick)
    actor.initialised(self) |> actor.returning(self) |> Ok
  })
  |> actor.on_message(fn(self, _tick) {
    hub.publish_event(hub, VmUpdated(vm.sample()))
    process.send_after(self, interval_ms, Tick)
    actor.continue(self)
  })
  |> actor.start
}

/// Telemetry as a supervised child.
pub fn supervised(
  hub: Subject(hub.Message),
) -> supervision.ChildSpecification(Subject(Tick)) {
  supervision.worker(fn() { start(hub) })
}
