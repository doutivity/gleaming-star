import client/ui/animator.{type Anim}
import client/ui/theme
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg

/// Shape of the border.
pub type Variant {
  /// Four corner brackets.
  Corners
  /// A full outline with cut corners.
  Octagon
  /// A single line along the bottom edge.
  Underline
}

/// A side of a frame.
pub type Side {
  Top
  Right
  Bottom
  Left
}

/// A corner of a frame.
pub type Corner {
  TopLeft
  TopRight
  BottomRight
  BottomLeft
}

/// One drawn piece of a border. Straight edges stretch along their own axis
/// only, so line thickness never distorts; diagonals and brackets live in
/// small fixed-size boxes at the corners.
pub type Segment {
  Edge(Side)
  Diagonal(Corner)
  Bracket(Corner)
}

/// The pieces of a variant, in the order they are drawn: each piece gets an
/// equal share of the animation's progress, so the line seems to travel
/// around the panel.
pub fn segments(variant: Variant) -> List(Segment) {
  case variant {
    Corners -> [
      Bracket(TopLeft),
      Bracket(TopRight),
      Bracket(BottomRight),
      Bracket(BottomLeft),
    ]
    Octagon -> [
      Edge(Top),
      Diagonal(TopRight),
      Edge(Right),
      Diagonal(BottomRight),
      Edge(Bottom),
      Diagonal(BottomLeft),
      Edge(Left),
      Diagonal(TopLeft),
    ]
    Underline -> [Edge(Bottom)]
  }
}

/// The SVG path of a segment inside its own box (see the `.frame__seg`
/// rules in styles.css). Strokes are 2 units wide and centred 1 unit in.
pub fn segment_path(segment: Segment) -> String {
  case segment {
    Edge(Top) -> "M0 1 H100"
    Edge(Right) -> "M1 0 V100"
    Edge(Bottom) -> "M100 1 H0"
    Edge(Left) -> "M1 100 V0"
    Diagonal(TopLeft) -> "M0 12 L12 0"
    Diagonal(TopRight) -> "M0 0 L12 12"
    Diagonal(BottomRight) -> "M12 0 L0 12"
    Diagonal(BottomLeft) -> "M12 12 L0 0"
    Bracket(TopLeft) -> "M1 14 V1 H14"
    Bracket(TopRight) -> "M0 1 H13 V14"
    Bracket(BottomRight) -> "M13 0 V13 H0"
    Bracket(BottomLeft) -> "M14 13 H1 V0"
  }
}

/// The `viewBox` of a segment's SVG.
pub fn segment_view_box(segment: Segment) -> String {
  case segment {
    Edge(Top) | Edge(Bottom) -> "0 0 100 2"
    Edge(Left) | Edge(Right) -> "0 0 2 100"
    Diagonal(_) -> "0 0 12 12"
    Bracket(_) -> "0 0 14 14"
  }
}

/// CSS class that positions a segment.
pub fn segment_class(segment: Segment) -> String {
  case segment {
    Edge(side) -> "frame__seg frame__seg--edge frame__seg--" <> side_name(side)
    Diagonal(corner) ->
      "frame__seg frame__seg--diagonal frame__seg--" <> corner_name(corner)
    Bracket(corner) ->
      "frame__seg frame__seg--bracket frame__seg--" <> corner_name(corner)
  }
}

fn side_name(side: Side) -> String {
  case side {
    Top -> "top"
    Right -> "right"
    Bottom -> "bottom"
    Left -> "left"
  }
}

fn corner_name(corner: Corner) -> String {
  case corner {
    TopLeft -> "top-left"
    TopRight -> "top-right"
    BottomRight -> "bottom-right"
    BottomLeft -> "bottom-left"
  }
}

/// CSS class for a variant.
pub fn variant_class(variant: Variant) -> String {
  case variant {
    Corners -> "frame--corners"
    Octagon -> "frame--octagon"
    Underline -> "frame--underline"
  }
}

/// A panel with a border that draws itself as `anim` progresses, then the
/// background fades in. `danger` turns it red and makes it pulse.
pub fn view(
  variant: Variant,
  danger danger: Bool,
  anim anim: Anim,
  content content: List(Element(msg)),
) -> Element(msg) {
  let class = case danger {
    True -> "frame " <> variant_class(variant) <> " frame--danger"
    False -> "frame " <> variant_class(variant)
  }
  let pieces = segments(variant)
  let count = list.length(pieces)
  html.div([attribute.class(class), ..theme.anim_attributes(anim)], [
    html.div(
      [
        attribute.class("frame__lines"),
        attribute.attribute("aria-hidden", "true"),
      ],
      list.index_map(pieces, fn(piece, index) {
        segment_view(piece, index, count)
      }),
    ),
    html.div([attribute.class("frame__bg")], []),
    html.div([attribute.class("frame__content")], content),
  ])
}

fn segment_view(segment: Segment, index: Int, count: Int) -> Element(msg) {
  svg.svg(
    [
      attribute.class(segment_class(segment)),
      attribute.attribute("viewBox", segment_view_box(segment)),
      attribute.attribute("preserveAspectRatio", "none"),
      attribute.styles([
        #("--i", int.to_string(index)),
        #("--n", int.to_string(count)),
      ]),
    ],
    [
      svg.path([
        attribute.class("frame__line"),
        attribute.attribute("d", segment_path(segment)),
        attribute.attribute("pathLength", "1"),
        attribute.attribute("fill", "none"),
      ]),
    ],
  )
}
