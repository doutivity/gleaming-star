import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list

/// Lifecycle of one animated element.
pub type Anim {
  Exited
  /// Appearing; `progress` runs 0.0..1.0.
  Entering(progress: Float)
  Entered
  /// Disappearing; `progress` is how much of the exit has elapsed, 0.0..1.0.
  Exiting(progress: Float)
}

/// How visible the element is, 0.0 (gone) to 1.0 (fully shown). This is the
/// value that reaches CSS as `--p`.
pub fn progress(anim: Anim) -> Float {
  case anim {
    Exited -> 0.0
    Entering(progress) -> progress
    Entered -> 1.0
    Exiting(progress) -> 1.0 -. progress
  }
}

/// Starts appearing. An element that is already on its way out reverses from
/// where it is, so rapid toggling never jumps.
pub fn enter(anim: Anim) -> Anim {
  case anim {
    Exited -> Entering(0.0)
    Exiting(progress) -> Entering(1.0 -. progress)
    Entering(_) | Entered -> anim
  }
}

/// Starts disappearing; the mirror image of `enter`.
pub fn exit(anim: Anim) -> Anim {
  case anim {
    Entered -> Exiting(0.0)
    Entering(progress) -> Exiting(1.0 -. progress)
    Exited | Exiting(_) -> anim
  }
}

/// Advances an animation by `dt_ms`. `duration_ms` is the length of the whole
/// transition in progress; zero or less finishes it at once, which is how
/// reduced motion is expressed.
pub fn tick(anim: Anim, dt_ms: Float, duration_ms: Float) -> Anim {
  case anim {
    Exited | Entered -> anim
    Entering(progress) ->
      case advance_progress(progress, dt_ms, duration_ms) {
        p if p >=. 1.0 -> Entered
        p -> Entering(p)
      }
    Exiting(progress) ->
      case advance_progress(progress, dt_ms, duration_ms) {
        p if p >=. 1.0 -> Exited
        p -> Exiting(p)
      }
  }
}

fn advance_progress(
  progress: Float,
  dt_ms: Float,
  duration_ms: Float,
) -> Float {
  case duration_ms <=. 0.0 {
    True -> 1.0
    False -> progress +. float.max(dt_ms, 0.0) /. duration_ms
  }
}

/// Like `tick`, choosing the entering or exiting duration by state.
pub fn advance(
  anim: Anim,
  dt_ms: Float,
  enter_ms: Float,
  exit_ms: Float,
) -> Anim {
  case anim {
    Exiting(_) -> tick(anim, dt_ms, exit_ms)
    _ -> tick(anim, dt_ms, enter_ms)
  }
}

/// True when nothing is moving.
pub fn is_settled(anim: Anim) -> Bool {
  case anim {
    Exited | Entered -> True
    Entering(_) | Exiting(_) -> False
  }
}

/// Value of the `data-anim` attribute.
pub fn state_name(anim: Anim) -> String {
  case anim {
    Exited -> "exited"
    Entering(_) -> "entering"
    Entered -> "entered"
    Exiting(_) -> "exiting"
  }
}

// STAGE: a parent with children that appear one after another.

/// A parent element and ordered children. Children do not start until the
/// parent has reached `Entered`, and then start `stagger_ms` apart.
pub type Stage {
  Stage(
    parent: Anim,
    children: List(Anim),
    /// Time since the parent reached `Entered`.
    clock_ms: Float,
    stagger_ms: Float,
  )
}

/// A stage with everything `Exited`.
pub fn new_stage(child_count: Int, stagger_ms: Float) -> Stage {
  Stage(
    parent: Exited,
    children: list.repeat(Exited, child_count),
    clock_ms: 0.0,
    stagger_ms:,
  )
}

/// Starts the parent; children follow once it is `Entered`.
pub fn stage_enter(stage: Stage) -> Stage {
  Stage(..stage, parent: enter(stage.parent), clock_ms: 0.0)
}

/// Everything leaves together.
pub fn stage_exit(stage: Stage) -> Stage {
  Stage(
    ..stage,
    parent: exit(stage.parent),
    children: list.map(stage.children, exit),
  )
}

/// Advances the whole stage by `dt_ms`.
pub fn stage_tick(
  stage: Stage,
  dt_ms: Float,
  enter_ms: Float,
  exit_ms: Float,
) -> Stage {
  let parent = advance(stage.parent, dt_ms, enter_ms, exit_ms)
  let clock_ms = case parent, stage.parent {
    // Count only time spent fully entered.
    Entered, Entered -> stage.clock_ms +. dt_ms
    _, _ -> 0.0
  }
  let children =
    list.index_map(stage.children, fn(child, index) {
      let due = int.to_float(index) *. stage.stagger_ms
      // Judged by the parent's state at the start of the tick, so children
      // never inherit the leftover time of the tick that finished the parent.
      let child = case stage.parent == Entered && clock_ms >=. due {
        True -> enter(child)
        False -> child
      }
      advance(child, dt_ms, enter_ms, exit_ms)
    })
  Stage(..stage, parent:, children:, clock_ms:)
}

/// Animation of child `index`; `Entered` if there is no such child.
pub fn stage_child(stage: Stage, index: Int) -> Anim {
  case list.drop(stage.children, index) {
    [child, ..] -> child
    [] -> Entered
  }
}

/// True when the parent and every child are settled.
pub fn stage_settled(stage: Stage) -> Bool {
  is_settled(stage.parent)
  && list.all(stage.children, is_settled)
  && stage_waiting_children(stage) == False
}

/// A parent that is `Entered` but still has `Exited` children has work to do:
/// they are waiting for their stagger slot.
fn stage_waiting_children(stage: Stage) -> Bool {
  stage.parent == Entered && list.any(stage.children, fn(c) { c == Exited })
}

// REGISTRY: in-flight one-off animations, such as a log line being deciphered.

/// Animations looked up by key. Anything missing counts as `Entered`, so
/// settled entries are dropped by `registry_tick` and the dictionary stays
/// small.
pub type Registry =
  Dict(String, Anim)

/// Animation for `key`; `Entered` when it is not tracked.
pub fn lookup(registry: Registry, key: String) -> Anim {
  case dict.get(registry, key) {
    Ok(anim) -> anim
    Error(Nil) -> Entered
  }
}

/// Restarts `key` from the beginning.
pub fn restart(registry: Registry, key: String) -> Registry {
  dict.insert(registry, key, Entering(0.0))
}

/// Advances every entry and forgets those that are fully entered.
pub fn registry_tick(
  registry: Registry,
  dt_ms: Float,
  enter_ms: Float,
  exit_ms: Float,
) -> Registry {
  dict.fold(registry, dict.new(), fn(acc, key, anim) {
    case advance(anim, dt_ms, enter_ms, exit_ms) {
      Entered -> acc
      next -> dict.insert(acc, key, next)
    }
  })
}

/// True if any entry is still moving.
pub fn registry_busy(registry: Registry) -> Bool {
  dict.fold(registry, False, fn(busy, _, anim) { busy || !is_settled(anim) })
}
