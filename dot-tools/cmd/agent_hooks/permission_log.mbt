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
    // write_file syncs every write by default; the Python append it replaced did not, and a lost line is harmless.
    sync=NoSync,
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
#borrow(buffer)
extern "C" fn format_local_time(
  seconds : Int64,
  buffer : FixedArray[Byte],
  size : Int32,
) -> Int32 = "agent_hooks_local_time"

///|
/// Formats like `time.strftime("%Y-%m-%dT%H:%M:%S%z")`.
fn local_timestamp(seconds : Int64) -> String {
  let buffer = FixedArray::make(64, b'\x00')
  let length = format_local_time(seconds, buffer, buffer.length())
  // strftime writes ASCII only.
  String::from_iter(buffer.iter().take(length).map(byte => byte.to_char()))
}
