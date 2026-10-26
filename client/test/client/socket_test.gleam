import client/socket
import gleam/list

pub fn backoff_doubles_up_to_ten_seconds_test() {
  assert list.map([0, 1, 2, 3, 4, 5, 6, 7], socket.backoff_ms)
    == [500, 1000, 2000, 4000, 8000, 10_000, 10_000, 10_000]
}

pub fn backoff_handles_huge_attempt_counts_test() {
  assert socket.backoff_ms(1_000_000) == 10_000
}
