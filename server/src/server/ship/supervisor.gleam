import gleam/list
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import server/names.{type Names}
import server/ship/subsystem

/// One `one_for_one` child per subsystem. A crash restarts only that
/// subsystem. The tolerance is generous so that a demo with many quick
/// INJECT FAULT clicks does not take the whole application down.
pub fn supervised(names: Names) -> supervision.ChildSpecification(Supervisor) {
  let hub = names.hub_subject(names)
  list.fold(
    names.subsystems,
    static_supervisor.new(static_supervisor.OneForOne)
      |> static_supervisor.restart_tolerance(intensity: 20, period: 10),
    fn(builder, entry) {
      static_supervisor.add(
        builder,
        subsystem.supervised(entry.0, entry.1, hub),
      )
    },
  )
  |> static_supervisor.supervised
}
