import gleam/int
import gleam/string

const mebibyte = 1_048_576

const gibibyte = 1_073_741_824

/// Time of day in UTC as `HH:MM:SS`, from milliseconds since the Unix epoch.
pub fn utc_clock(epoch_ms: Int) -> String {
  let seconds_of_day = epoch_ms / 1000 % 86_400
  clock(seconds_of_day)
}

/// A duration as `HH:MM:SS`, with a leading `Nd ` once it passes a day.
pub fn uptime(ms: Int) -> String {
  let total_seconds = int.max(ms, 0) / 1000
  let days = total_seconds / 86_400
  let time = clock(total_seconds % 86_400)
  case days {
    0 -> time
    _ -> int.to_string(days) <> "d " <> time
  }
}

fn clock(seconds_of_day: Int) -> String {
  let hours = seconds_of_day / 3600
  let minutes = seconds_of_day % 3600 / 60
  let seconds = seconds_of_day % 60
  pad2(hours) <> ":" <> pad2(minutes) <> ":" <> pad2(seconds)
}

/// A byte count in MiB, or GiB from one gibibyte up, with one decimal.
pub fn memory(bytes: Int) -> String {
  case bytes >= gibibyte {
    True -> one_decimal(bytes, gibibyte) <> " GiB"
    False -> one_decimal(bytes, mebibyte) <> " MiB"
  }
}

fn one_decimal(value: Int, unit: Int) -> String {
  let tenths = { int.max(value, 0) * 10 + unit / 2 } / unit
  int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10)
}

fn pad2(value: Int) -> String {
  string.pad_start(int.to_string(value), 2, "0")
}
