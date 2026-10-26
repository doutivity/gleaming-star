import client/ui/animator.{Entered, Entering, Exited}
import client/ui/theme

pub fn css_number_test() {
  assert theme.css_number(0.0) == "0.000"
  assert theme.css_number(1.0) == "1.000"
  assert theme.css_number(0.5) == "0.500"
  assert theme.css_number(0.0625) == "0.063"
  assert theme.css_number(0.004) == "0.004"
  assert theme.css_number(0.3333333) == "0.333"
}

pub fn css_number_is_never_scientific_test() {
  assert theme.css_number(0.00000001) == "0.000"
  assert theme.css_number(123_456.789) == "123456.789"
}

pub fn css_number_negative_test() {
  assert theme.css_number(-0.25) == "-0.250"
  assert theme.css_number(-1.5) == "-1.500"
}

pub fn durations_match_the_css_tokens_test() {
  // styles.css: --dur-enter 400ms, --dur-exit 300ms, --stagger 80ms.
  assert theme.enter_ms == 400.0
  assert theme.exit_ms == 300.0
  assert theme.stagger_ms == 80.0
}

pub fn anim_attributes_are_a_state_and_a_variable_test() {
  assert theme.anim_attributes(Exited) != []
  assert theme.anim_attributes(Entering(0.5)) != theme.anim_attributes(Entered)
}
