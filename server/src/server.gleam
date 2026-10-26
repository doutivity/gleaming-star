import gleam/erlang/application
import gleam/erlang/process
import server/app
import server/config
import server/names

/// Reads the configuration and starts the supervision tree. Failing to start
/// is a startup error, so it is allowed to crash.
pub fn main() -> Nil {
  let config = config.load()
  let assert Ok(priv) = application.priv_directory("server")
  let assert Ok(_) = app.start(config, priv, names.new())
  process.sleep_forever()
}
