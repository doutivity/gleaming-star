import client/ui/animator.{type Anim}
import client/ui/frame
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Colour scheme of a button.
pub type Variant {
  Primary
  /// For destructive actions such as INJECT FAULT.
  Danger
}

/// CSS class for a variant.
pub fn variant_class(variant: Variant) -> String {
  case variant {
    Primary -> "btn--primary"
    Danger -> "btn--danger"
  }
}

/// A framed button. It is a real `<button>`, so keyboard focus and activation
/// work natively; `disabled` removes both the click handler and focus.
/// `description` is the accessible name, so that several buttons with the
/// same visible label, such as REBOOT, can be told apart.
pub fn view(
  label: String,
  describing description: String,
  variant variant: Variant,
  disabled disabled: Bool,
  anim anim: Anim,
  on_click on_click: msg,
) -> Element(msg) {
  let handlers = case disabled {
    True -> []
    False -> [event.on_click(on_click)]
  }
  frame.view(frame.Octagon, danger: False, anim: anim, content: [
    html.button(
      [
        attribute.class("btn " <> variant_class(variant)),
        attribute.type_("button"),
        attribute.aria_label(description),
        attribute.disabled(disabled),
        ..handlers
      ],
      [html.text(label)],
    ),
  ])
}
