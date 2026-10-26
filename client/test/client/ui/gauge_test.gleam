import client/ui/gauge.{Critical, Elevated, Low}

pub fn level_thresholds_test() {
  assert gauge.level(0) == Low
  assert gauge.level(59) == Low
  assert gauge.level(60) == Elevated
  assert gauge.level(84) == Elevated
  assert gauge.level(85) == Critical
  assert gauge.level(100) == Critical
}

pub fn level_classes_test() {
  assert gauge.level_class(Low) == "level-low"
  assert gauge.level_class(Elevated) == "level-elevated"
  assert gauge.level_class(Critical) == "level-critical"
}

pub fn lit_segments_test() {
  assert gauge.lit_segments(0) == 0
  assert gauge.lit_segments(50) == 10
  assert gauge.lit_segments(100) == 20
  // Rounds to the nearest segment (5% each).
  assert gauge.lit_segments(2) == 0
  assert gauge.lit_segments(3) == 1
  assert gauge.lit_segments(97) == 19
}

pub fn lit_segments_clamps_out_of_range_test() {
  assert gauge.lit_segments(-30) == 0
  assert gauge.lit_segments(250) == 20
}
