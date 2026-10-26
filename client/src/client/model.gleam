import client/route.{type Route}
import client/ui/animator.{type Registry, type Stage}
import client/ui/log.{type Line, Line}
import client/ui/sparkline
import client/ui/theme
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import lustre_websocket.{type WebSocket, type WebSocketEvent}
import shared/protocol.{
  type ClientCommand, type ServerEvent, type Subsystem, type SubsystemId,
  type VmStats, Logged, Nominal, Offline, Snapshot, SubsystemUpdated, VmUpdated,
}

/// How many journal lines the client keeps, matching the server's tail.
pub const log_limit = 200

/// How many panels a page staggers in (children of its `Stage`): the
/// dashboard uses 7 (five subsystems, telemetry, log), the kit page 7 too.
pub const stage_panels = 7

/// State of the connection to the server.
pub type Link {
  Connecting
  Online
  Lost
}

/// Everything the page knows: server data, connection state, animation state.
pub type Model {
  Model(
    route: Route,
    link: Link,
    /// Failed connection attempts since the link last opened; drives backoff.
    attempts: Int,
    socket: Option(WebSocket),
    ship_name: String,
    subsystems: Dict(SubsystemId, Subsystem),
    /// Subsystems that crashed and have not come back to `Nominal` yet.
    /// `Offline` lasts only milliseconds, so this is what keeps the failure
    /// visible through the whole reboot.
    failed: Set(SubsystemId),
    vm: Option(VmStats),
    /// Oldest first.
    log: List(Line),
    next_line_id: Int,
    /// Latest samples for the sparklines, oldest first.
    memory_history: List(Int),
    process_history: List(Int),
    /// Frames from the server that could not be decoded.
    bad_frames: Int,
    /// Wall-clock time in ms since the epoch, updated every second.
    now_ms: Int,
    /// Page entrance: a parent with staggered children.
    stage: Stage,
    /// One-off animations in flight, such as lines being deciphered.
    anims: Registry,
    /// The user prefers reduced motion: every transition is instant.
    reduced_motion: Bool,
    /// True while the single animation-frame loop is running.
    loop_running: Bool,
    last_frame_ms: Option(Float),
    /// Frames drawn so far; seeds the decipher scramble.
    frame: Int,
    /// Lines added by hand on the kit page.
    kit_log: List(Line),
  )
}

/// Everything that can happen: socket traffic, timers, frames, user input.
pub type Msg {
  /// Something happened on the WebSocket.
  Socket(WebSocketEvent)
  /// The backoff timer fired: try to connect again.
  Reconnect
  /// An animation frame, with the browser's timestamp in milliseconds.
  Frame(Float)
  /// The URL hash changed.
  RouteChanged(Route)
  /// Kit page: replay the page entrance from scratch.
  KitReplay
  /// Kit page: enter or exit the whole stage.
  KitToggle
  /// Kit page: restart the live decipher sample.
  KitDecipher
  /// Kit page: append a line to the sample log.
  KitAddLine
  /// The system's reduced-motion setting is now this.
  MotionPreferenceChanged(Bool)
  /// The clock ticked; carries the time in ms since the epoch.
  ClockTick(Int)
  /// The operator pressed a control: send this command to the server.
  Operate(ClientCommand)
  /// The power slider of a subsystem was released at this value (text).
  PowerChanged(SubsystemId, String)
  /// A control that is shown but does nothing.
  Noop
}

/// The model before the first connection. Nothing is animating yet.
pub fn new(route: Route) -> Model {
  Model(
    route:,
    link: Connecting,
    attempts: 0,
    socket: None,
    ship_name: "",
    subsystems: dict.new(),
    failed: set.new(),
    vm: None,
    log: [],
    next_line_id: 0,
    memory_history: [],
    process_history: [],
    bad_frames: 0,
    now_ms: 0,
    stage: animator.new_stage(stage_panels, theme.stagger_ms),
    anims: dict.new(),
    reduced_motion: False,
    loop_running: False,
    last_frame_ms: None,
    frame: 0,
    kit_log: [],
  )
}

/// Folds a server event into the model. New journal lines start deciphering.
pub fn apply_event(model: Model, event: ServerEvent) -> Model {
  case event {
    Snapshot(ship_name:, subsystems:, vm:, log:) -> {
      let kept = list.drop(log, list.length(log) - log_limit)
      let #(lines, next_line_id) = number_lines(kept, model.next_line_id)
      let anims = case ship_name != model.ship_name {
        True -> animator.restart(model.anims, ship_name_key)
        False -> model.anims
      }
      Model(
        ..model,
        ship_name:,
        subsystems: list.fold(subsystems, dict.new(), fn(acc, subsystem) {
          dict.insert(acc, subsystem.id, subsystem)
        }),
        failed: subsystems
          |> list.filter(fn(subsystem) { subsystem.status == Offline })
          |> list.map(fn(subsystem) { subsystem.id })
          |> set.from_list,
        vm: Some(vm),
        memory_history: [vm.memory_bytes],
        process_history: [vm.process_count],
        log: lines,
        next_line_id:,
        anims:,
      )
    }
    SubsystemUpdated(subsystem) -> update_subsystem(model, subsystem)
    VmUpdated(vm) ->
      Model(
        ..model,
        vm: Some(vm),
        memory_history: push_capped(model.memory_history, vm.memory_bytes),
        process_history: push_capped(model.process_history, vm.process_count),
      )
    Logged(entry) -> {
      let line = Line(id: model.next_line_id, entry:)
      let lines = list.append(model.log, [line])
      Model(
        ..model,
        log: list.drop(lines, list.length(lines) - log_limit),
        next_line_id: model.next_line_id + 1,
        anims: animator.restart(model.anims, log.anim_key(line.id)),
      )
    }
  }
}

/// Key of the ship name's decipher animation.
pub const ship_name_key = "ship-name"

/// Key of a subsystem card title's decipher animation.
pub fn title_key(id: SubsystemId) -> String {
  "title-" <> protocol.subsystem_name(id)
}

/// True while `id` has crashed and not yet come back to `Nominal`.
pub fn is_failed(model: Model, id: SubsystemId) -> Bool {
  set.contains(model.failed, id)
}

/// Stores a subsystem update and tracks failure. A crash shows up as
/// `Offline`, or as a restart count that went up. The failure ends when the
/// subsystem is `Nominal` again; a controlled reboot never starts one. The
/// card title is deciphered again whenever that changes.
fn update_subsystem(model: Model, subsystem: Subsystem) -> Model {
  let restarted = case dict.get(model.subsystems, subsystem.id) {
    Ok(previous) -> subsystem.restarts > previous.restarts
    Error(Nil) -> False
  }
  let was_failed = is_failed(model, subsystem.id)
  let failed = case subsystem.status {
    Offline -> set.insert(model.failed, subsystem.id)
    Nominal -> set.delete(model.failed, subsystem.id)
    _ ->
      case restarted {
        True -> set.insert(model.failed, subsystem.id)
        False -> model.failed
      }
  }
  let anims = case was_failed == set.contains(failed, subsystem.id) {
    True -> model.anims
    False -> animator.restart(model.anims, title_key(subsystem.id))
  }
  Model(
    ..model,
    subsystems: dict.insert(model.subsystems, subsystem.id, subsystem),
    failed:,
    anims:,
  )
}

fn number_lines(
  entries: List(protocol.LogEntry),
  first_id: Int,
) -> #(List(Line), Int) {
  let lines =
    list.index_map(entries, fn(entry, index) {
      Line(id: first_id + index, entry:)
    })
  #(lines, first_id + list.length(entries))
}

fn push_capped(history: List(Int), value: Int) -> List(Int) {
  let next = list.append(history, [value])
  list.drop(next, list.length(next) - sparkline.max_points)
}

/// Subsystems in display order; ones not yet reported are skipped.
pub fn ordered_subsystems(model: Model) -> List(Subsystem) {
  list.filter_map(protocol.all_subsystems, dict.get(model.subsystems, _))
}

/// True while any animation still has frames to draw.
pub fn is_animating(model: Model) -> Bool {
  !animator.stage_settled(model.stage) || animator.registry_busy(model.anims)
}
