import client/ui/frame.{
  BottomLeft, BottomRight, Bracket, Corners, Diagonal, Edge, Octagon, Top,
  TopLeft, TopRight, Underline,
}
import gleam/list
import gleam/string

pub fn variant_classes_test() {
  assert frame.variant_class(Corners) == "frame--corners"
  assert frame.variant_class(Octagon) == "frame--octagon"
  assert frame.variant_class(Underline) == "frame--underline"
}

pub fn octagon_is_four_edges_and_four_diagonals_test() {
  let pieces = frame.segments(Octagon)
  assert list.length(pieces) == 8
  assert list.length(list.filter(pieces, is_edge)) == 4
  assert list.length(list.filter(pieces, is_diagonal)) == 4
}

pub fn octagon_alternates_edges_and_diagonals_test() {
  // The line travels edge, corner, edge, corner...
  assert list.index_map(frame.segments(Octagon), fn(piece, i) {
      is_edge(piece) == { i % 2 == 0 }
    })
    |> list.all(fn(ok) { ok })
}

pub fn corners_are_four_brackets_test() {
  assert frame.segments(Corners)
    == [
      Bracket(TopLeft),
      Bracket(TopRight),
      Bracket(BottomRight),
      Bracket(BottomLeft),
    ]
}

pub fn underline_is_one_edge_test() {
  assert list.length(frame.segments(Underline)) == 1
}

pub fn every_segment_has_a_drawable_path_test() {
  list.each(
    list.flatten([
      frame.segments(Octagon),
      frame.segments(Corners),
      frame.segments(Underline),
    ]),
    fn(piece) {
      assert string.starts_with(frame.segment_path(piece), "M")
      assert frame.segment_view_box(piece) != ""
      assert string.contains(frame.segment_class(piece), "frame__seg")
    },
  )
}

pub fn edges_stretch_along_their_axis_only_test() {
  assert frame.segment_view_box(Edge(Top)) == "0 0 100 2"
  assert frame.segment_view_box(Edge(frame.Right)) == "0 0 2 100"
  assert frame.segment_view_box(Diagonal(TopRight)) == "0 0 12 12"
  assert frame.segment_view_box(Diagonal(BottomLeft)) == "0 0 12 12"
  assert frame.segment_view_box(Diagonal(BottomRight)) == "0 0 12 12"
}

pub fn the_line_is_continuous_around_the_octagon_test() {
  // The top edge ends at the top-right diagonal's start (its top-left point).
  assert frame.segment_path(Edge(Top)) == "M0 1 H100"
  assert frame.segment_path(Diagonal(TopRight)) == "M0 0 L12 12"
}

fn is_edge(piece) -> Bool {
  case piece {
    Edge(_) -> True
    _ -> False
  }
}

fn is_diagonal(piece) -> Bool {
  case piece {
    Diagonal(_) -> True
    _ -> False
  }
}

pub fn segment_classes_are_distinct_per_position_test() {
  let classes = list.map(frame.segments(Octagon), frame.segment_class)
  assert list.length(list.unique(classes)) == 8
  assert frame.segment_class(Bracket(BottomRight))
    == "frame__seg frame__seg--bracket frame__seg--bottom-right"
}
