import client/browser
import client/model.{
  type Model, type Msg, Connecting, Lost, Model, Online, Reconnect,
}
import client/socket
import client/ui/animator
import client/ui/log.{Line}
import client/ui/theme
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/effect.{type Effect}
import lustre_websocket.{OnBinaryMessage, OnClose, OnOpen, OnTextMessage}
import shared/codec
import shared/protocol.{
  type ClientCommand, Critical, Info, LogEntry, SetPower, Warning,
}

/// Longest gap between frames that counts as elapsed time; a background tab
/// resuming must not make animations jump to the end in a single step.
const max_frame_gap_ms = 100.0

/// Connects, listens for hash changes and plays the page entrance.
pub fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let #(model, loop) =
    Model(
      ..model.new(browser.current_route()),
      reduced_motion: browser.prefers_reduced_motion(),
    )
    |> restart_stage
    |> ensure_loop
  #(
    model,
    effect.batch([
      socket.connect(),
      browser.listen_for_route_changes(),
      browser.start_clock(),
      browser.listen_for_motion_preference(),
      loop,
    ]),
  )
}

/// The Elm-style update function: every message becomes a new model and,
/// possibly, an effect.
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    model.Socket(OnOpen(ws)) -> #(
      Model(..model, link: Online, attempts: 0, socket: Some(ws)),
      effect.none(),
    )
    model.Socket(OnTextMessage(text)) -> {
      let #(model, effect) = receive(model, text) |> ensure_loop
      #(model, effect)
    }
    model.Socket(OnBinaryMessage(_)) -> #(
      Model(..model, bad_frames: model.bad_frames + 1),
      effect.none(),
    )
    model.Socket(OnClose(_)) | model.Socket(lustre_websocket.InvalidUrl) ->
      connection_lost(model)
    Reconnect -> #(Model(..model, link: Connecting), socket.connect())
    model.Frame(timestamp) -> frame(model, timestamp)
    model.RouteChanged(route) ->
      Model(..model, route:) |> restart_stage |> ensure_loop
    model.KitReplay -> restart_stage(model) |> ensure_loop
    model.KitToggle -> toggle_stage(model) |> ensure_loop
    model.KitDecipher ->
      Model(..model, anims: animator.restart(model.anims, "kit-decipher"))
      |> ensure_loop
    model.KitAddLine -> add_kit_line(model) |> ensure_loop
    model.MotionPreferenceChanged(reduced_motion) -> {
      let model = Model(..model, reduced_motion:)
      Model(
        ..model,
        stage: animator.Stage(..model.stage, stagger_ms: stagger_ms(model)),
      )
      |> ensure_loop
    }
    model.ClockTick(now_ms) -> #(Model(..model, now_ms:), effect.none())
    model.Operate(command) -> #(model, send(model, command))
    model.PowerChanged(id, text) ->
      case int.parse(text) {
        Ok(level) -> #(
          model,
          send(model, SetPower(id, int.clamp(level, 0, 100))),
        )
        Error(Nil) -> #(model, effect.none())
      }
    model.Noop -> #(model, effect.none())
  }
}

/// A decodable frame updates the model; garbage is counted and ignored.
fn receive(model: Model, text: String) -> Model {
  case codec.decode_event(text) {
    Ok(event) -> model.apply_event(model, event)
    Error(_) -> Model(..model, bad_frames: model.bad_frames + 1)
  }
}

/// Marks the link lost and schedules the next attempt with exponential
/// backoff. `attempts` only resets when a connection opens.
fn connection_lost(model: Model) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, link: Lost, attempts: model.attempts + 1, socket: None),
    socket.reconnect_after(model.attempts),
  )
}

/// Sends a command over the open socket; with no socket there is nobody to
/// tell, and the controls are disabled anyway.
fn send(model: Model, command: ClientCommand) -> Effect(Msg) {
  case model.socket {
    Some(ws) -> socket.send(ws, command)
    None -> effect.none()
  }
}

// ANIMATION LOOP

/// One animation frame: advance everything, and ask for the next frame only
/// if something is still moving.
fn frame(model: Model, timestamp: Float) -> #(Model, Effect(Msg)) {
  let dt = case model.last_frame_ms {
    Some(previous) -> float.clamp(timestamp -. previous, 0.0, max_frame_gap_ms)
    None -> 0.0
  }
  let #(enter_ms, exit_ms) = durations(model)
  let model =
    Model(
      ..model,
      stage: animator.stage_tick(model.stage, dt, enter_ms, exit_ms),
      anims: animator.registry_tick(model.anims, dt, enter_ms, exit_ms),
      frame: model.frame + 1,
      last_frame_ms: Some(timestamp),
    )
  case model.is_animating(model) {
    True -> #(model, browser.request_frame())
    False -> #(
      Model(..model, loop_running: False, last_frame_ms: None),
      effect.none(),
    )
  }
}

/// Starts the frame loop if there is something to animate and it is not
/// already running.
fn ensure_loop(model: Model) -> #(Model, Effect(Msg)) {
  case model.loop_running || !model.is_animating(model) {
    True -> #(model, effect.none())
    False -> #(
      Model(..model, loop_running: True, last_frame_ms: None),
      browser.request_frame(),
    )
  }
}

/// Enter and exit durations. Zero means instant, which is how reduced motion
/// is applied: the animator finishes any transition on its next tick.
fn durations(model: Model) -> #(Float, Float) {
  case model.reduced_motion {
    True -> #(0.0, 0.0)
    False -> #(theme.enter_ms, theme.exit_ms)
  }
}

fn stagger_ms(model: Model) -> Float {
  case model.reduced_motion {
    True -> 0.0
    False -> theme.stagger_ms
  }
}

// STAGE

fn enter_stage(model: Model) -> Model {
  Model(..model, stage: animator.stage_enter(model.stage))
}

/// Everything hidden again, then the entrance plays from the start.
fn restart_stage(model: Model) -> Model {
  Model(
    ..model,
    stage: animator.new_stage(model.stage_panels, stagger_ms(model))
      |> animator.stage_enter,
  )
}

fn toggle_stage(model: Model) -> Model {
  case model.stage.parent {
    animator.Entered | animator.Entering(_) ->
      Model(..model, stage: animator.stage_exit(model.stage))
    animator.Exited | animator.Exiting(_) -> enter_stage(model)
  }
}

// KIT

/// Appends a sample line, cycling through the severities.
fn add_kit_line(model: Model) -> Model {
  let id = model.next_line_id
  let entry = case list.length(model.kit_log) % 3 {
    0 -> LogEntry(0, Info, "KIT", "REROUTING POWER TO AUXILIARY BUS")
    1 -> LogEntry(0, Warning, "KIT", "COOLANT PRESSURE BELOW THRESHOLD")
    _ -> LogEntry(0, Critical, "KIT", "SUBSYSTEM FAILURE")
  }
  Model(
    ..model,
    kit_log: list.append(model.kit_log, [Line(id:, entry:)]),
    next_line_id: id + 1,
    anims: animator.restart(model.anims, log.anim_key(id)),
  )
}
