import envoy
import gleam/int
import gleam/result

/// Runtime settings read from the environment.
pub type Config {
  Config(port: Int, ship_name: String)
}

const default_port = 8000

const default_ship_name = "ISV GLEAMING STAR"

/// Loads `PORT` and `SHIP_NAME`, falling back to defaults when unset or invalid.
pub fn load() -> Config {
  Config(
    port: envoy.get("PORT")
      |> result.try(int.parse)
      |> result.unwrap(default_port),
    ship_name: envoy.get("SHIP_NAME") |> result.unwrap(default_ship_name),
  )
}
