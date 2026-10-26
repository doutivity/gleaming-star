import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import mist
import server/config.{type Config}
import server/hub
import server/names.{type Names}
import server/router
import server/ship/supervisor as ship_supervisor
import server/telemetry

/// The whole application as one supervision tree. `RestForOne` follows the
/// start order: if the hub dies, everything that depends on it (ship,
/// telemetry, web) restarts after it; a subsystem crash never reaches this
/// level because the ship supervisor absorbs it.
pub fn start(
  config: Config,
  priv: String,
  names: Names,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.restart_tolerance(intensity: 5, period: 10)
  |> static_supervisor.add(hub.supervised(names.hub, config.ship_name))
  |> static_supervisor.add(ship_supervisor.supervised(names))
  |> static_supervisor.add(telemetry.supervised(names.hub_subject(names)))
  |> static_supervisor.add(web(config, priv, names))
  |> static_supervisor.start
}

fn web(config: Config, priv: String, names: Names) {
  fn(req) { router.handle(req, priv, names) }
  |> mist.new
  |> mist.bind("0.0.0.0")
  |> mist.port(config.port)
  |> mist.supervised
}
