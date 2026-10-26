import client/update
import client/view
import lustre

/// Starts the Lustre app on `#app`. Failing to start is a startup error.
pub fn main() -> Nil {
  let app = lustre.application(update.init, update.update, view.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
