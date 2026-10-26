import client/ui/animator.{Entered, Entering, Exited}
import client/ui/decipher
import gleam/list
import gleam/string

const text = "SUBSYSTEM FAILURE 42"

pub fn fully_revealed_is_the_original_test() {
  assert decipher.render(text, 1.0, 5) == text
  assert decipher.render(text, 1.5, 5) == text
}

pub fn deterministic_test() {
  assert decipher.render(text, 0.3, 9) == decipher.render(text, 0.3, 9)
}

pub fn seed_changes_the_scramble_test() {
  assert decipher.render(text, 0.0, 1) != decipher.render(text, 0.0, 2)
}

pub fn length_is_preserved_at_every_step_test() {
  list.each([0.0, 0.1, 0.5, 0.99, 1.0], fn(p) {
    assert string.length(decipher.render(text, p, 3)) == string.length(text)
  })
}

pub fn spaces_are_preserved_test() {
  let scrambled = decipher.render(text, 0.0, 11)
  assert string.to_graphemes(scrambled)
    |> list.index_map(fn(char, i) { #(i, char == " ") })
    == string.to_graphemes(text)
    |> list.index_map(fn(char, i) { #(i, char == " ") })
}

pub fn reveals_left_to_right_test() {
  // Half of 20 characters: the first ten are exact.
  let half = decipher.render(text, 0.5, 4)
  assert string.slice(half, 0, 10) == string.slice(text, 0, 10)
}

pub fn unrevealed_characters_are_glyphs_test() {
  let scrambled = decipher.render(text, 0.0, 8)
  let allowed = string.to_graphemes(decipher.glyphs) |> list.append([" "])
  assert list.all(string.to_graphemes(scrambled), fn(c) {
    list.contains(allowed, c)
  })
}

pub fn reveal_grows_monotonically_test() {
  let counts =
    list.map([0.0, 0.2, 0.4, 0.6, 0.8, 1.0], fn(p) {
      decipher.revealed_count(20, p)
    })
  assert counts == [0, 4, 8, 12, 16, 20]
}

pub fn reveal_count_is_clamped_test() {
  assert decipher.revealed_count(10, -1.0) == 0
  assert decipher.revealed_count(10, 2.0) == 10
}

pub fn empty_text_test() {
  assert decipher.render("", 0.5, 1) == ""
}

pub fn handles_huge_and_negative_seeds_test() {
  assert string.length(decipher.render(text, 0.0, 1_000_000_007)) == 20
  assert string.length(decipher.render(text, 0.0, -42)) == 20
}

pub fn view_does_not_panic_for_every_state_test() {
  // Smoke test: building the element for each animation state.
  list.each([Exited, Entering(0.5), Entered], fn(anim) {
    let _ = decipher.view(text, anim, 3)
    Nil
  })
}
