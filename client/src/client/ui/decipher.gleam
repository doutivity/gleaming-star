import client/ui/animator.{type Anim}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// Characters shown while text is still scrambled.
pub const glyphs = "ABCDEF0123456789#$%&@*+=<>/\\"

/// The text as it looks at `progress` (0.0..1.0): characters on the left are
/// already revealed, the rest are glyphs picked from `seed`. Spaces are kept
/// as they are. The same inputs always give the same output.
pub fn render(text: String, progress: Float, seed: Int) -> String {
  let chars = string.to_graphemes(text)
  let revealed = revealed_count(list.length(chars), progress)
  let pool = string.to_graphemes(glyphs)
  let pool_size = list.length(pool)
  chars
  |> list.index_map(fn(char, index) {
    case index < revealed || char == " " {
      True -> char
      False -> glyph_at(pool, pool_size, hash(seed, index))
    }
  })
  |> string.concat
}

/// How many characters (from the left) are revealed at `progress`.
pub fn revealed_count(length: Int, progress: Float) -> Int {
  float.truncate(float.clamp(progress, 0.0, 1.0) *. int.to_float(length))
}

fn glyph_at(pool: List(String), size: Int, hash: Int) -> String {
  case list.drop(pool, hash % size) {
    [glyph, ..] -> glyph
    [] -> "#"
  }
}

/// Cheap deterministic mixing of a seed and a position. Stays well below 2^53
/// so it is exact in JavaScript.
fn hash(seed: Int, index: Int) -> Int {
  let mixed =
    { { int.absolute_value(seed) % 65_521 } * 31 + index } * 2_654_435_761
  { mixed % 4_294_967_296 } / 65_536
}

/// The deciphering text as an element. Screen readers get the final text;
/// the scrambled glyphs are hidden from them.
pub fn view(text: String, anim: Anim, seed: Int) -> Element(msg) {
  case animator.progress(anim) {
    p if p >=. 1.0 -> html.span([attribute.class("decipher")], [html.text(text)])
    p ->
      html.span([attribute.class("decipher is-active")], [
        html.span([attribute.class("sr-only")], [html.text(text)]),
        html.span([attribute.attribute("aria-hidden", "true")], [
          html.text(render(text, p, seed)),
        ]),
      ])
  }
}
