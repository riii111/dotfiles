// Records Claude Code's permission prompts and auto mode denials for permission-analyze, in the format the Python hook
// wrote. It never answers, so the prompt or denial goes on unchanged, and a failure to log is ignored.

///|
let max_command : Int32 = 500

///|
let max_reason : Int32 = 300

///|
async fn permission_log(event : Json, home~ : String) -> Unit {
  guard event is Object(fields) && home != "" else { return }
  let field = (name : String) => fields.get(name).unwrap_or(Json::null())
  let record : Array[(String, Json)] = [
    (
      "time",
      Json::string(local_timestamp(@env.now().reinterpret_as_int64() / 1000L)),
    ),
    ("event", field("hook_event_name")),
    ("session", field("session_id")),
    ("cwd", field("cwd")),
    ("mode", field("permission_mode")),
    ("tool", field("tool_name")),
  ]
  // Only PermissionDenied carries a reason: the matched rule, or a note that the classifier gave no verdict.
  if truthy(field("reason")) {
    record.push(
      ("reason", Json::string(prefix(text(field("reason")), max_reason))),
    )
  }
  if field("tool_name") is String("Bash") {
    let input = match field("tool_input") {
      Object(input) => input
      _ => Map([])
    }
    let command = input.get("command").unwrap_or(Json::string(""))
    record.push(("command", Json::string(prefix(text(command), max_command))))
    record.push(
      (
        "unsandboxed",
        Json::boolean(
          truthy(input.get("dangerouslyDisableSandbox").unwrap_or(Json::null())),
        ),
      ),
    )
  }
  let dir = home + "/.local/state/claude"
  // Commands can carry secrets, so only the user may read the log.
  @fs.mkdir(dir, permission=0o700, recursive=true, allow_exist=true) catch {
    _ => return
  }
  @fs.write_file(
    dir + "/permission-events.jsonl",
    python_json_line(record),
    create_mode=OpenOrCreate,
    permission=0o600,
    append=true,
  ) catch {
    _ => ()
  }
}

///|
/// Python's `json.dumps` separators, so lines match the ones the earlier hook appended.
fn python_json_line(record : Array[(String, Json)]) -> String {
  let fields = record.map(pair => {
    Json::string(pair.0).stringify() + ": " + pair.1.stringify()
  })
  "{" + fields.join(", ") + "}\n"
}

///|
fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    Number(number, ..) => number != 0.0
    String(text) => text != ""
    Array(items) => !items.is_empty()
    Object(map) => !map.is_empty()
    True => true
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(text) => text
    other => other.stringify()
  }
}

///|
/// The first `limit` code points, as Python slices a string.
fn prefix(text : String, limit : Int32) -> String {
  let builder = StringBuilder()
  let mut count = 0
  for char in text {
    guard count < limit else { break }
    builder.write_char(char)
    count += 1
  }
  builder.to_string()
}

///|
extern "C" fn utc_offset(seconds : Int64) -> Int32 = "agent_hooks_utc_offset"

///|
fn local_timestamp(seconds : Int64) -> String {
  format_timestamp(seconds, utc_offset(seconds))
}

///|
/// Formats like `time.strftime("%Y-%m-%dT%H:%M:%S%z")`.
fn format_timestamp(seconds : Int64, offset : Int32) -> String {
  let shifted = seconds + offset.to_int64()
  let days = floor_div(shifted, 86400L)
  let clock = (shifted - days * 86400L).to_int()
  // Howard Hinnant's days-to-civil algorithm.
  let z = days + 719468L
  let era = floor_div(z, 146097L)
  let day_of_era = z - era * 146097L
  let year_of_era = (
      day_of_era -
      day_of_era / 1460L +
      day_of_era / 36524L -
      day_of_era / 146096L
    ) /
    365L
  let day_of_year = day_of_era -
    (365L * year_of_era + year_of_era / 4L - year_of_era / 100L)
  let month_index = (5L * day_of_year + 2L) / 153L
  let day = day_of_year - (153L * month_index + 2L) / 5L + 1L
  let month = if month_index < 10L {
    month_index + 3L
  } else {
    month_index - 9L
  }
  let year = year_of_era + era * 400L + (if month <= 2L { 1L } else { 0L })
  let sign = if offset < 0 { "-" } else { "+" }
  let minutes = offset.abs() / 60
  "\{pad(year.to_int(), 4)}-\{pad(month.to_int(), 2)}-\{pad(day.to_int(), 2)}T" +
  "\{pad(clock / 3600, 2)}:\{pad(clock / 60 % 60, 2)}:\{pad(clock % 60, 2)}" +
  "\{sign}\{pad(minutes / 60, 2)}\{pad(minutes % 60, 2)}"
}

///|
fn floor_div(value : Int64, divisor : Int64) -> Int64 {
  let quotient = value / divisor
  if value % divisor < 0L {
    quotient - 1L
  } else {
    quotient
  }
}

///|
fn pad(value : Int32, width : Int32) -> String {
  let digits = value.to_string()
  "0".repeat(width - digits.length()) + digits
}
