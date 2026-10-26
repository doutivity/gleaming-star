import client/model.{
  type Msg, ClockTick, Frame, MotionPreferenceChanged, RouteChanged,
}
import client/route.{type Route}
import gleam/result
import lustre/effect.{type Effect}
import plinth/browser/location
import plinth/browser/window
import plinth/javascript/date
import plinth/javascript/global

/// The route for the current URL hash.
pub fn current_route() -> Route {
  window.self()
  |> window.location
  |> location.hash
  |> result.unwrap("")
  |> route.parse
}

/// Asks for one `Frame` message on the next animation frame. The update
/// function re-requests it while anything is animating: that is the single
/// frame loop of the whole app.
pub fn request_frame() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    window.request_animation_frame(fn(timestamp) { dispatch(Frame(timestamp)) })
    Nil
  })
}

/// Sends `RouteChanged` whenever the URL hash changes.
pub fn listen_for_route_changes() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    window.add_event_listener("hashchange", fn(_event) {
      dispatch(RouteChanged(current_route()))
    })
  })
}

/// Sends `ClockTick` now and then once a second.
pub fn start_clock() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let tick = fn() { dispatch(ClockTick(date.get_time(date.now()))) }
    tick()
    global.set_interval(1000, tick)
    Nil
  })
}

/// True when the user asked the system for reduced motion.
@external(javascript, "./reduced_motion_ffi.mjs", "prefers_reduced_motion")
pub fn prefers_reduced_motion() -> Bool

@external(javascript, "./reduced_motion_ffi.mjs", "on_reduced_motion_change")
fn on_reduced_motion_change(callback: fn(Bool) -> Nil) -> Nil

/// Sends `MotionPreferenceChanged` when the user flips the system setting.
pub fn listen_for_motion_preference() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    on_reduced_motion_change(fn(reduced) {
      dispatch(MotionPreferenceChanged(reduced))
    })
  })
}
