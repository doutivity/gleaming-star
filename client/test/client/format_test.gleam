import client/format

pub fn utc_clock_test() {
  assert format.utc_clock(0) == "00:00:00"
  assert format.utc_clock(1000) == "00:00:01"
  assert format.utc_clock(3_661_000) == "01:01:01"
  // 2026-10-26 23:59:59 UTC
  assert format.utc_clock(1_793_059_199_000) == "23:59:59"
}

pub fn utc_clock_wraps_at_midnight_test() {
  assert format.utc_clock(86_400_000) == "00:00:00"
  assert format.utc_clock(86_399_999) == "23:59:59"
}

pub fn uptime_test() {
  assert format.uptime(0) == "00:00:00"
  assert format.uptime(107_294) == "00:01:47"
  assert format.uptime(3_600_000) == "01:00:00"
  assert format.uptime(-5) == "00:00:00"
}

pub fn uptime_counts_days_test() {
  assert format.uptime(86_400_000) == "1d 00:00:00"
  assert format.uptime(90_061_000) == "1d 01:01:01"
}

pub fn memory_test() {
  assert format.memory(0) == "0.0 MiB"
  assert format.memory(1_048_576) == "1.0 MiB"
  assert format.memory(43_321_072) == "41.3 MiB"
  assert format.memory(1_572_864) == "1.5 MiB"
}

pub fn memory_switches_to_gib_test() {
  assert format.memory(1_073_741_823) == "1024.0 MiB"
  assert format.memory(1_073_741_824) == "1.0 GiB"
  assert format.memory(3_221_225_472) == "3.0 GiB"
}
