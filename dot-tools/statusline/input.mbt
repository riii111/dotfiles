// Reads the session state that Claude Code passes to its status line command.
// A field of the wrong type makes the whole input unreadable, as Go's encoding/json did for the earlier status line.

///|
/// A usage limit: its used percentage when known, and when it resets in seconds since the epoch.
pub(all) struct RateLimit {
  used_percentage : Double?
  resets_at : Double?
}

///|
pub(all) struct Input {
  model : String
  context_percentage : Double
  lines_added : Int64
  lines_removed : Int64
  cwd : String
  worktree : String
  original_branch : String
  five_hour : RateLimit
  seven_day : RateLimit
}

///|
priv suberror Unreadable

///|
/// Parses the status line input, or returns `None` when it is not the expected JSON.
pub fn parse_input(text : String) -> Input? {
  let json = @json.parse(text, preserve_number_repr=true) catch {
    _ => return None
  }
  try read_input(json) catch {
    _ => None
  } noraise {
    input => Some(input)
  }
}

///|
fn read_input(json : Json) -> Input raise Unreadable {
  let root = object(Some(json))
  let model = object(root.get("model"))
  let context = object(root.get("context_window"))
  let cost = object(root.get("cost"))
  let worktree = object(root.get("worktree"))
  let limits = object(root.get("rate_limits"))
  ignore(number(cost.get("total_cost_usd")))
  let name = string(model.get("display_name"))
  {
    model: if name == "" {
      "Unknown"
    } else {
      name
    },
    context_percentage: number(context.get("used_percentage")).unwrap_or(0.0),
    lines_added: integer(cost.get("total_lines_added")),
    lines_removed: integer(cost.get("total_lines_removed")),
    cwd: string(root.get("cwd")),
    worktree: string(worktree.get("name")),
    original_branch: string(worktree.get("original_branch")),
    five_hour: rate_limit(limits.get("five_hour")),
    seven_day: rate_limit(limits.get("seven_day")),
  }
}

///|
/// An absent or null field reads as empty, as with Go's zero values.
fn object(json : Json?) -> Map[String, Json] raise Unreadable {
  match json {
    None | Some(Null) => {}
    Some(Object(fields)) => fields
    _ => raise Unreadable
  }
}

///|
fn string(json : Json?) -> String raise Unreadable {
  match json {
    None | Some(Null) => ""
    Some(String(value)) => value
    _ => raise Unreadable
  }
}

///|
fn number(json : Json?) -> Double? raise Unreadable {
  match json {
    None | Some(Null) => None
    Some(Number(value, ..)) => Some(value)
    _ => raise Unreadable
  }
}

///|
/// Like Go, an integer field takes only an integer literal, so `2.0` or `1e2` makes the input unreadable.
fn integer(json : Json?) -> Int64 raise Unreadable {
  match json {
    None | Some(Null) => 0
    Some(Number(value, repr~)) => {
      let literal = repr.unwrap_or(value.to_string())
      @string.parse_int64(literal) catch {
        _ => raise Unreadable
      }
    }
    _ => raise Unreadable
  }
}

///|
fn rate_limit(json : Json?) -> RateLimit raise Unreadable {
  let fields = object(json)
  {
    used_percentage: number(fields.get("used_percentage")),
    resets_at: reset_time(fields.get("resets_at")),
  }
}

///|
/// Reads an epoch number, an RFC 3339 time or a numeric string; anything else is ignored, never an error.
fn reset_time(json : Json?) -> Double? {
  match json {
    Some(Number(seconds, ..)) if seconds > 0.0 => Some(seconds)
    Some(String(text)) =>
      match parse_rfc3339(text) {
        Some(seconds) => Some(seconds)
        None =>
          match (Some(@string.parse_double(text)) catch { _ => None }) {
            Some(seconds) if seconds > 0.0 => Some(seconds)
            _ => None
          }
      }
    _ => None
  }
}

///|
/// Parses `YYYY-MM-DDTHH:MM:SS[.fraction]` followed by `Z`, `±HH:MM` or nothing for UTC.
fn parse_rfc3339(text : String) -> Double? {
  let chars = text.iter().collect()
  guard chars.length() >= 19 &&
    chars[4] == '-' &&
    chars[7] == '-' &&
    chars[10] == 'T' &&
    chars[13] == ':' &&
    chars[16] == ':' else {
    return None
  }
  guard digits(chars, 0, 4) is Some(year) &&
    digits(chars, 5, 2) is Some(month) &&
    digits(chars, 8, 2) is Some(day) &&
    digits(chars, 11, 2) is Some(hour) &&
    digits(chars, 14, 2) is Some(minute) &&
    digits(chars, 17, 2) is Some(second) else {
    return None
  }
  guard month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= days_in_month(year, month) &&
    hour < 24 &&
    minute < 60 &&
    second < 60 else {
    return None
  }
  let mut index = 19
  let mut fraction = 0.0
  if chars.get(index) is Some('.') {
    let start = index + 1
    index = start
    let mut scale = 0.1
    while index < chars.length() && chars[index].is_ascii_digit() {
      fraction += (chars[index].to_int() - '0'.to_int()).to_double() * scale
      scale /= 10.0
      index += 1
    }
    guard index > start else { return None }
  }
  let offset = match chars[index:].to_owned() {
    [] | ['Z'] => 0
    [sign, h1, h2, ':', m1, m2] if sign == '+' || sign == '-' => {
      guard digits([h1, h2, m1, m2], 0, 2) is Some(hours) &&
        digits([h1, h2, m1, m2], 2, 2) is Some(minutes) &&
        hours < 24 &&
        minutes < 60 else {
        return None
      }
      let seconds = hours * 3600 + minutes * 60
      if sign == '+' {
        seconds
      } else {
        -seconds
      }
    }
    _ => return None
  }
  let days = days_from_civil(year, month, day)
  Some(
    (days * 86400 + hour * 3600 + minute * 60 + second - offset).to_double() +
    fraction,
  )
}

///|
fn digits(chars : Array[Char], start : Int32, count : Int32) -> Int32? {
  let mut value = 0
  for index in start..<(start + count) {
    guard chars.get(index) is Some(char) && char.is_ascii_digit() else {
      return None
    }
    value = value * 10 + (char.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
fn days_in_month(year : Int32, month : Int32) -> Int32 {
  match month {
    2 =>
      if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 {
        29
      } else {
        28
      }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
/// Days since 1970-01-01 for a proleptic Gregorian date.
fn days_from_civil(year : Int32, month : Int32, day : Int32) -> Int32 {
  let year = if month <= 2 { year - 1 } else { year }
  let era = (if year >= 0 { year } else { year - 399 }) / 400
  let year_of_era = year - era * 400
  let month_index = if month > 2 { month - 3 } else { month + 9 }
  let day_of_year = (153 * month_index + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era * 146097 + day_of_era - 719468
}
