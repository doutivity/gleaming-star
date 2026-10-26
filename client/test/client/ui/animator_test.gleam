import client/ui/animator.{Entered, Entering, Exited, Exiting}
import gleam/dict
import gleam/float
import gleam/list

// Single animation

pub fn progress_test() {
  assert animator.progress(Exited) == 0.0
  assert animator.progress(Entering(0.25)) == 0.25
  assert animator.progress(Entered) == 1.0
  assert animator.progress(Exiting(0.25)) == 0.75
}

pub fn enter_test() {
  assert animator.enter(Exited) == Entering(0.0)
  assert animator.enter(Entering(0.4)) == Entering(0.4)
  assert animator.enter(Entered) == Entered
}

pub fn enter_reverses_an_exit_from_where_it_is_test() {
  // 25% through leaving means 75% visible; entering resumes from 75%.
  assert animator.enter(Exiting(0.25)) == Entering(0.75)
}

pub fn exit_test() {
  assert animator.exit(Entered) == Exiting(0.0)
  assert animator.exit(Exiting(0.4)) == Exiting(0.4)
  assert animator.exit(Exited) == Exited
}

pub fn exit_reverses_an_enter_from_where_it_is_test() {
  assert animator.exit(Entering(0.25)) == Exiting(0.75)
}

pub fn visible_amount_is_continuous_across_reversal_test() {
  assert close(animator.progress(animator.exit(Entering(0.3))), 0.3)
  assert close(animator.progress(animator.enter(Exiting(0.3))), 0.7)
}

fn close(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <. 0.000001
}

pub fn tick_entering_test() {
  assert animator.tick(Entering(0.0), 100.0, 400.0) == Entering(0.25)
  assert animator.tick(Entering(0.75), 100.0, 400.0) == Entered
  assert animator.tick(Entering(0.9), 1000.0, 400.0) == Entered
}

pub fn tick_exiting_test() {
  assert animator.tick(Exiting(0.0), 150.0, 300.0) == Exiting(0.5)
  assert animator.tick(Exiting(0.5), 150.0, 300.0) == Exited
}

pub fn tick_leaves_settled_states_alone_test() {
  assert animator.tick(Exited, 100.0, 400.0) == Exited
  assert animator.tick(Entered, 100.0, 400.0) == Entered
}

pub fn zero_duration_finishes_at_once_test() {
  // Reduced motion: every transition is instant.
  assert animator.tick(Entering(0.0), 0.0, 0.0) == Entered
  assert animator.tick(Exiting(0.0), 0.0, 0.0) == Exited
}

pub fn negative_time_never_runs_backwards_test() {
  assert animator.tick(Entering(0.5), -100.0, 400.0) == Entering(0.5)
}

pub fn advance_picks_the_duration_by_state_test() {
  assert animator.advance(Entering(0.0), 100.0, 400.0, 200.0) == Entering(0.25)
  assert animator.advance(Exiting(0.0), 100.0, 400.0, 200.0) == Exiting(0.5)
}

pub fn full_cycle_test() {
  let anim =
    animator.enter(Exited)
    |> run(400.0, 100.0)
  assert anim == Entered
  let anim = animator.exit(anim) |> run(300.0, 100.0)
  assert anim == Exited
}

fn run(anim, total_ms: Float, step_ms: Float) {
  case total_ms <=. 0.0 {
    True -> anim
    False ->
      run(
        animator.advance(anim, step_ms, 400.0, 300.0),
        total_ms -. step_ms,
        step_ms,
      )
  }
}

pub fn is_settled_test() {
  assert animator.is_settled(Exited)
  assert animator.is_settled(Entered)
  assert animator.is_settled(Entering(0.5)) == False
  assert animator.is_settled(Exiting(0.5)) == False
}

pub fn state_name_test() {
  assert list.map(
      [Exited, Entering(0.1), Entered, Exiting(0.1)],
      animator.state_name,
    )
    == ["exited", "entering", "entered", "exiting"]
}

// Stage

fn step(stage, dt) {
  animator.stage_tick(stage, dt, 400.0, 300.0)
}

pub fn new_stage_is_hidden_and_settled_test() {
  let stage = animator.new_stage(3, 80.0)
  assert stage.parent == Exited
  assert stage.children == [Exited, Exited, Exited]
  assert animator.stage_settled(stage)
}

pub fn children_wait_for_the_parent_test() {
  let stage = animator.new_stage(2, 80.0) |> animator.stage_enter
  let stage = step(stage, 200.0)
  assert stage.parent == Entering(0.5)
  assert stage.children == [Exited, Exited]
  assert animator.stage_settled(stage) == False
}

pub fn children_start_after_the_parent_has_entered_test() {
  let stage = animator.new_stage(2, 80.0) |> animator.stage_enter
  // Parent finishes on this tick; children have not started yet.
  let stage = step(stage, 400.0)
  assert stage.parent == Entered
  assert stage.children == [Exited, Exited]
  assert animator.stage_settled(stage) == False
  // Next tick: first child is due immediately (index 0), second at 80 ms.
  let stage = step(stage, 40.0)
  assert stage.children == [Entering(0.1), Exited]
  let stage = step(stage, 40.0)
  assert list.map(stage.children, animator.is_settled) == [False, False]
}

pub fn children_are_staggered_test() {
  let stage =
    animator.new_stage(3, 80.0)
    |> animator.stage_enter
    |> step(400.0)
  let stage = step(stage, 100.0)
  // 100 ms after the parent finished: children 0 (due 0) and 1 (due 80) run.
  assert list.map(stage.children, fn(c) { c != Exited }) == [True, True, False]
  let stage = step(stage, 100.0)
  assert list.map(stage.children, fn(c) { c != Exited }) == [True, True, True]
}

pub fn stage_settles_fully_entered_test() {
  let stage = animator.new_stage(3, 80.0) |> animator.stage_enter
  let stage = tick_until_settled(stage, 1000)
  assert stage.parent == Entered
  assert stage.children == [Entered, Entered, Entered]
}

fn tick_until_settled(stage, remaining) {
  case animator.stage_settled(stage) || remaining == 0 {
    True -> stage
    False -> tick_until_settled(step(stage, 16.0), remaining - 1)
  }
}

pub fn stage_exit_takes_everything_out_together_test() {
  let stage =
    animator.new_stage(2, 80.0)
    |> animator.stage_enter
    |> tick_until_settled(1000)
    |> animator.stage_exit
  assert stage.parent == Exiting(0.0)
  assert stage.children == [Exiting(0.0), Exiting(0.0)]
  let stage = tick_until_settled(stage, 1000)
  assert stage.parent == Exited
  assert stage.children == [Exited, Exited]
}

pub fn exited_children_do_not_reenter_while_the_parent_leaves_test() {
  let stage =
    animator.new_stage(2, 80.0)
    |> animator.stage_enter
    |> tick_until_settled(1000)
    |> animator.stage_exit
    |> step(100.0)
  assert stage.parent != Entered
  assert list.all(stage.children, fn(c) { c != Entered })
}

pub fn stage_can_be_replayed_test() {
  let stage =
    animator.new_stage(2, 80.0)
    |> animator.stage_enter
    |> tick_until_settled(1000)
    |> animator.stage_exit
    |> tick_until_settled(1000)
    |> animator.stage_enter
    |> tick_until_settled(1000)
  assert stage.parent == Entered
  assert stage.children == [Entered, Entered]
}

pub fn stage_child_lookup_test() {
  let stage = animator.new_stage(2, 80.0)
  assert animator.stage_child(stage, 0) == Exited
  assert animator.stage_child(stage, 1) == Exited
  // Unknown children are shown rather than hidden.
  assert animator.stage_child(stage, 9) == Entered
}

// Registry

pub fn lookup_defaults_to_entered_test() {
  assert animator.lookup(dict.new(), "x") == Entered
}

pub fn restart_and_tick_test() {
  let registry = animator.restart(dict.new(), "line")
  assert animator.lookup(registry, "line") == Entering(0.0)
  assert animator.registry_busy(registry)
  let registry = animator.registry_tick(registry, 200.0, 400.0, 300.0)
  assert animator.lookup(registry, "line") == Entering(0.5)
}

pub fn finished_entries_are_forgotten_test() {
  let registry =
    animator.restart(dict.new(), "line")
    |> animator.registry_tick(400.0, 400.0, 300.0)
  assert dict.size(registry) == 0
  assert animator.registry_busy(registry) == False
  assert animator.lookup(registry, "line") == Entered
}

pub fn exited_entries_are_kept_test() {
  let registry = dict.insert(dict.new(), "hidden", Exited)
  let registry = animator.registry_tick(registry, 100.0, 400.0, 300.0)
  assert animator.lookup(registry, "hidden") == Exited
  assert animator.registry_busy(registry) == False
}
