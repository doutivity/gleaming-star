import client/model.{
  ClockTick, Connecting, Frame, KitAddLine, KitReplay, KitToggle, Lost,
  MotionPreferenceChanged, Operate, PowerChanged, Reconnect, RouteChanged,
  Socket,
}
import client/route.{Dashboard, Kit}
import client/ui/animator
import client/update
import gleam/list
import gleam/option.{None, Some}
import lustre_websocket.{
  AbnormalClose, InvalidUrl, Normal, OnBinaryMessage, OnClose, OnTextMessage,
}
import shared/codec
import shared/protocol.{
  Info, InjectFault, LogEntry, Logged, Reactor, VmStats, VmUpdated,
}

fn fresh() {
  model.new(Dashboard)
}

fn closed(model) {
  update.update(model, Socket(OnClose(AbnormalClose))).0
}

// Socket

pub fn valid_frame_updates_the_model_test() {
  let vm = VmStats(1, 2, 3, 4, 5)
  let text = codec.encode_event(VmUpdated(vm))
  let #(model, _) = update.update(fresh(), Socket(OnTextMessage(text)))
  assert model.vm == Some(vm)
  assert model.bad_frames == 0
}

pub fn invalid_frames_are_counted_and_ignored_test() {
  let #(model, _) = update.update(fresh(), Socket(OnTextMessage("not json")))
  let #(model, _) =
    update.update(model, Socket(OnTextMessage("{\"type\":\"nope\"}")))
  let #(model, _) = update.update(model, Socket(OnBinaryMessage(<<1, 2, 3>>)))
  assert model.bad_frames == 3
  assert model.vm == None
}

pub fn close_marks_link_lost_test() {
  let model = closed(fresh())
  assert model.link == Lost
  assert model.attempts == 1
  assert model.socket == None
}

pub fn invalid_url_is_treated_as_lost_test() {
  let #(model, _) = update.update(fresh(), Socket(InvalidUrl))
  assert model.link == Lost
}

pub fn attempts_grow_across_failed_reconnects_test() {
  let model = closed(fresh())
  let #(model, _) = update.update(model, Reconnect)
  assert model.link == Connecting
  let model = closed(model)
  let #(model, _) = update.update(model, Reconnect)
  let model = closed(model)
  assert model.attempts == 3
}

pub fn clean_close_also_reconnects_test() {
  let #(model, _) = update.update(fresh(), Socket(OnClose(Normal)))
  assert model.link == Lost
}

// Frame loop

pub fn new_log_line_starts_the_frame_loop_test() {
  let text = codec.encode_event(Logged(LogEntry(0, Info, "t", "m")))
  let #(model, _) = update.update(fresh(), Socket(OnTextMessage(text)))
  assert model.loop_running
}

pub fn quiet_events_do_not_start_the_loop_test() {
  let text = codec.encode_event(VmUpdated(VmStats(1, 2, 3, 4, 5)))
  let #(model, _) = update.update(fresh(), Socket(OnTextMessage(text)))
  assert model.loop_running == False
}

pub fn frames_advance_the_stage_test() {
  let #(model, _) = update.update(fresh(), KitReplay)
  assert model.loop_running
  let #(model, _) = update.update(model, Frame(1000.0))
  // The first frame only records the time.
  assert model.stage.parent == animator.Entering(0.0)
  let #(model, _) = update.update(model, Frame(1100.0))
  assert model.stage.parent == animator.Entering(0.25)
  assert model.frame == 2
}

pub fn long_gaps_are_capped_test() {
  let #(model, _) = update.update(fresh(), KitReplay)
  let #(model, _) = update.update(model, Frame(0.0))
  let #(model, _) = update.update(model, Frame(60_000.0))
  // A resumed tab advances by at most 100 ms, not to the end.
  assert model.stage.parent == animator.Entering(0.25)
}

pub fn loop_stops_when_everything_has_settled_test() {
  let #(model, _) = update.update(fresh(), KitReplay)
  let model = run_frames(model, 0.0, 200)
  assert model.stage == settled_stage(model)
  assert model.loop_running == False
  assert model.last_frame_ms == None
}

fn run_frames(model: model.Model, at: Float, remaining: Int) -> model.Model {
  case remaining {
    0 -> model
    _ ->
      case model.loop_running {
        False -> model
        True -> {
          let #(next, _) = update.update(model, Frame(at))
          run_frames(next, at +. 16.0, remaining - 1)
        }
      }
  }
}

fn settled_stage(model: model.Model) {
  assert animator.stage_settled(model.stage)
  assert model.stage.parent == animator.Entered
  model.stage
}

// Stage controls and routing

pub fn route_change_restarts_the_entrance_test() {
  let #(model, _) = update.update(fresh(), RouteChanged(Kit))
  assert model.route == Kit
  assert model.stage.parent == animator.Entering(0.0)
  assert model.loop_running
}

pub fn toggle_exits_then_enters_test() {
  let model = run_frames(update.update(fresh(), KitReplay).0, 0.0, 200)
  let #(model, _) = update.update(model, KitToggle)
  assert model.stage.parent == animator.Exiting(0.0)
  let model = run_frames(model, 5000.0, 200)
  assert model.stage.parent == animator.Exited
  let #(model, _) = update.update(model, KitToggle)
  assert model.stage.parent == animator.Entering(0.0)
}

pub fn kit_lines_are_added_and_deciphered_test() {
  let #(model, _) = update.update(fresh(), KitAddLine)
  let #(model, _) = update.update(model, KitAddLine)
  assert list.length(model.kit_log) == 2
  assert model.next_line_id == 2
  assert model.loop_running
}

// Clock and commands

pub fn clock_tick_stores_the_time_test() {
  let #(model, _) = update.update(fresh(), ClockTick(1_793_059_199_000))
  assert model.now_ms == 1_793_059_199_000
}

pub fn commands_without_a_socket_do_nothing_test() {
  // Nothing to send over: the model is unchanged and no frame loop starts.
  let #(after, _) = update.update(fresh(), Operate(InjectFault(Reactor)))
  assert after == fresh()
}

pub fn unparsable_slider_values_are_ignored_test() {
  let #(after, _) = update.update(fresh(), PowerChanged(Reactor, "abc"))
  assert after == fresh()
}

pub fn slider_values_are_accepted_test() {
  let #(after, _) = update.update(fresh(), PowerChanged(Reactor, "75"))
  assert after == fresh()
}

// Reduced motion

fn reduced() {
  model.Model(..model.new(Dashboard), reduced_motion: True)
}

pub fn reduced_motion_replay_finishes_in_a_few_frames_test() {
  let #(model, _) = update.update(reduced(), KitReplay)
  let model = run_frames(model, 0.0, 10)
  // No 400 ms entrance, no 80 ms stagger: all settled almost at once.
  assert model.stage.parent == animator.Entered
  assert model.stage.children
    == [
      animator.Entered,
      animator.Entered,
      animator.Entered,
      animator.Entered,
      animator.Entered,
      animator.Entered,
      animator.Entered,
    ]
  assert model.frame <= 4
  assert model.loop_running == False
}

pub fn reduced_motion_has_no_stagger_test() {
  let #(model, _) = update.update(reduced(), KitReplay)
  assert model.stage.stagger_ms == 0.0
  let #(model, _) = update.update(fresh(), KitReplay)
  assert model.stage.stagger_ms == 80.0
}

pub fn reduced_motion_skips_decipher_test() {
  let text = codec.encode_event(Logged(LogEntry(0, Info, "t", "m")))
  let #(model, _) = update.update(reduced(), Socket(OnTextMessage(text)))
  let model = run_frames(model, 0.0, 5)
  // The new line is already fully revealed after the first frames.
  assert animator.lookup(model.anims, "log-0") == animator.Entered
  assert model.loop_running == False
}

pub fn preference_change_applies_to_the_running_stage_test() {
  let #(model, _) = update.update(fresh(), KitReplay)
  let #(model, _) = update.update(model, MotionPreferenceChanged(True))
  assert model.reduced_motion
  assert model.stage.stagger_ms == 0.0
  let model = run_frames(model, 0.0, 10)
  assert animator.stage_settled(model.stage)
  assert model.stage.parent == animator.Entered
}

pub fn preference_can_be_turned_back_off_test() {
  let #(model, _) = update.update(reduced(), MotionPreferenceChanged(False))
  assert model.reduced_motion == False
  assert model.stage.stagger_ms == 80.0
}
