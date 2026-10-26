import client/ui/sparkline
import gleam/int
import gleam/list
import gleam/string

pub fn empty_series_test() {
  assert sparkline.points([]) == ""
}

pub fn two_points_span_the_full_box_test() {
  // Width 120, height 32, padding 2: low at the bottom, high at the top.
  assert sparkline.points([0, 10]) == "0.0,30.0 120.0,2.0"
}

pub fn higher_values_are_drawn_higher_test() {
  assert sparkline.points([10, 0]) == "0.0,2.0 120.0,30.0"
}

pub fn flat_series_is_a_centre_line_test() {
  assert sparkline.points([5, 5, 5]) == "0.0,16.0 60.0,16.0 120.0,16.0"
}

pub fn single_point_becomes_a_flat_line_test() {
  assert sparkline.points([7]) == "0.0,16.0 120.0,16.0"
}

pub fn only_the_latest_60_points_are_drawn_test() {
  let values =
    int.range(from: 0, to: 100, with: [], run: fn(acc, i) { [i, ..acc] })
    |> list.reverse
  let points = sparkline.points(values) |> string.split(" ")
  assert list.length(points) == sparkline.max_points
  // The window starts at value 40 (the lowest in view) and ends at 99.
  assert list.first(points) == Ok("0.0,30.0")
  assert list.last(points) == Ok("120.0,2.0")
}

pub fn negative_values_work_test() {
  assert sparkline.points([-10, 10]) == "0.0,30.0 120.0,2.0"
}
