///|
test "log lines escape like Python's json.dumps without ensure_ascii" {
  let line = python_json_line([
    ("time", "T"),
    ("event", "PermissionDenied"),
    ("session", Json::null()),
    ("command", "é\"\n\t\u{1}\u{7f}\u{2028}"),
    ("unsandboxed", true),
  ])
  assert_eq(
    line, "{\"time\": \"T\", \"event\": \"PermissionDenied\", \"session\": null, \"command\": \"é\\\"\\n\\t\\u0001\u{7f}\u{2028}\", \"unsandboxed\": true}\n",
  )
}

///|
test "timestamps carry the local offset like %z" {
  assert_eq(format_timestamp(0L, 0), "1970-01-01T00:00:00+0000")
  assert_eq(format_timestamp(1700000000L, 32400), "2023-11-15T07:13:20+0900")
  assert_eq(format_timestamp(1700000000L, -18000), "2023-11-14T17:13:20-0500")
  assert_eq(format_timestamp(951782400L, -12600), "2000-02-28T20:30:00-0330")
}

///|
async test "permission-log appends a private record of a Bash prompt" {
  let home = @fs.tmpdir(prefix="permission-log")
  defer @fs.rmdir(home, recursive=true)
  let event : Json = {
    "hook_event_name": "PermissionRequest",
    "session_id": "s1",
    "cwd": "/repo",
    "permission_mode": "auto",
    "tool_name": "Bash",
    "tool_input": {
      "command": "あ".repeat(600),
      "dangerouslyDisableSandbox": true,
    },
  }
  permission_log(event, home~)
  permission_log(
    {
      "hook_event_name": "PermissionDenied",
      "reason": "x".repeat(400),
      "tool_name": "Read",
    },
    home~,
  )
  let path = home + "/.local/state/claude/permission-events.jsonl"
  let lines = @fs.read_file(path).text().split("\n").collect()
  assert_eq(lines.length(), 3)
  guard @json.parse(lines[0].to_owned())
    is {
      "event": "PermissionRequest",
      "session": "s1",
      "cwd": "/repo",
      "mode": "auto",
      "tool": "Bash",
      "command": String(command),
      "unsandboxed": True,
      "time": String(time),
      ..
    } else {
    fail("unexpected record: \{lines[0]}")
  }
  assert_eq(command.iter().count(), 500)
  assert_eq(time.length(), 24)
  guard @json.parse(lines[1].to_owned())
    is { "reason": String(reason), "session": Null, .. } &&
    !lines[1].contains("command") else {
    fail("unexpected record: \{lines[1]}")
  }
  assert_eq(reason.length(), 300)
  let (_, listing, _) = @process.collect_output("ls", ["-l", path])
  assert_true(listing.text().has_prefix("-rw-------"))
}

///|
async test "permission-log ignores input it cannot use" {
  let home = @fs.tmpdir(prefix="permission-log")
  defer @fs.rmdir(home, recursive=true)
  permission_log(Json::string("not an event"), home~)
  permission_log({ "tool_name": "Bash" }, home="")
  assert_false(@fs.exists(home + "/.local"))
}
