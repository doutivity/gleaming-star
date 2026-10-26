import gleam/erlang/atom.{type Atom}
import shared/protocol.{type VmStats, VmStats}

@external(erlang, "erlang", "system_info")
fn system_info(item: Atom) -> Int

@external(erlang, "erlang", "memory")
fn memory(item: Atom) -> Int

@external(erlang, "erlang", "statistics")
fn statistics_int(item: Atom) -> Int

@external(erlang, "erlang", "statistics")
fn statistics_pair(item: Atom) -> #(Int, Int)

@external(erlang, "erlang", "system_time")
fn system_time(unit: Atom) -> Int

/// Samples the Erlang VM right now.
pub fn sample() -> VmStats {
  VmStats(
    process_count: system_info(atom.create("process_count")),
    memory_bytes: memory(atom.create("total")),
    run_queue: statistics_int(atom.create("run_queue")),
    schedulers: system_info(atom.create("schedulers_online")),
    // `wall_clock` is `{TotalMs, MsSinceLastCall}`; the total is the uptime.
    uptime_ms: statistics_pair(atom.create("wall_clock")).0,
  )
}

/// Wall-clock time in milliseconds since the Unix epoch.
pub fn now_ms() -> Int {
  system_time(atom.create("millisecond"))
}
