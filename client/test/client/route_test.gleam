import client/route.{Dashboard, Kit}

pub fn parse_test() {
  assert route.parse("#/kit") == Kit
  assert route.parse("#/kit/") == Kit
  // plinth hands over the hash without its "#".
  assert route.parse("/kit") == Kit
  assert route.parse("/kit/") == Kit
  assert route.parse("") == Dashboard
  assert route.parse("#/") == Dashboard
  assert route.parse("#/unknown") == Dashboard
}
