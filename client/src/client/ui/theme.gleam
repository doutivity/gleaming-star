import client/ui/animator.{type Anim}
import gleam/float
import gleam/int
import lustre/attribute.{type Attribute}

// These mirror --dur-enter, --dur-exit and --stagger in styles.css. The CSS
// tokens drive plain CSS transitions; the animator needs the numbers.

/// Length of an enter transition.
pub const enter_ms = 400.0

/// Length of an exit transition.
pub const exit_ms = 300.0

/// Delay between siblings appearing.
pub const stagger_ms = 80.0

/// A number for use in a CSS custom property: three decimals, never in
/// scientific notation.
pub fn css_number(value: Float) -> String {
  let thousandths = float.round(value *. 1000.0)
  let whole = thousandths / 1000
  let fraction = int.absolute_value(thousandths % 1000)
  let padded = case fraction {
    f if f < 10 -> "00" <> int.to_string(f)
    f if f < 100 -> "0" <> int.to_string(f)
    f -> int.to_string(f)
  }
  let sign = case thousandths < 0 && whole == 0 {
    True -> "-"
    False -> ""
  }
  sign <> int.to_string(whole) <> "." <> padded
}

/// The attributes through which an animation reaches CSS: `data-anim` for the
/// state and `--p` for how visible it is.
pub fn anim_attributes(anim: Anim) -> List(Attribute(msg)) {
  [
    attribute.attribute("data-anim", animator.state_name(anim)),
    attribute.style("--p", css_number(animator.progress(anim))),
  ]
}
