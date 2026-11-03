///|
/// 2026-11-03T13:00:00Z.
let now : Double = 1793710800.0

///|
fn plain(text : String) -> String {
  let result = StringBuilder()
  let mut escaped = false
  for char in text {
    if escaped {
      escaped = !char.is_ascii_alphabetic()
    } else if char == '\u{1b}' {
      escaped = true
    } else {
      result.write_char(char)
    }
  }
  result.to_string()
}

///|
fn line(json : String, branch~ : String = "", width~ : Int32 = 0) -> String {
  guard @statusline.parse_input(json) is Some(input) else {
    return "unreadable"
  }
  plain(@statusline.render(input, branch, width, now))
}

///|
test "the segments show the model, context, limits, branch and changed lines" {
  let json =
    #|{"model": {"display_name": "Opus"}, "context_window": {"used_percentage": 49.5},
    #| "cost": {"total_lines_added": 3, "total_lines_removed": 1},
    #| "rate_limits": {"five_hour": {"used_percentage": 37, "resets_at": "2026-11-03T14:30:00Z"},
    #|                 "seven_day": {"used_percentage": 88, "resets_at": 1793878200}}}
  assert_eq(
    line(json, branch="main"),
    "🤖 Opus │ 📊 50% │ 5h ◔ 37%(1h30m) 7d ● 88%(1d22h) │ 🔀 main │ +3/-1",
  )
}

///|
test "a worktree replaces the branch and missing limits show a dash" {
  let json =
    #|{"model": {"display_name": ""}, "worktree": {"name": "task", "original_branch": "main"},
    #| "rate_limits": {"five_hour": {"used_percentage": null}, "seven_day": {"used_percentage": -1}}}
  assert_eq(
    line(json, branch="ignored"),
    "🤖 Unknown │ 📊 0% │ 5h - 7d - │ 🌳 task ← main",
  )
}

///|
test "reset times accept RFC 3339, local offsets and epoch strings" {
  for
    resets_at in [
      "\"2026-11-03T22:05:00+09:00\"", "\"2026-11-03T13:05:00.5Z\"", "\"2026-11-03T13:05:00\"",
      "\"1793711100\"", "1793711100",
    ] {
    let json = "{\"rate_limits\": {\"five_hour\": {\"used_percentage\": 1, \"resets_at\": \{resets_at}}}}"
    assert_true(line(json).contains("5h ○ 1%(5m)"))
  }
  for resets_at in ["\"2026-13-01T00:00:00Z\"", "\"garbage\"", "true", "-5"] {
    let json = "{\"rate_limits\": {\"five_hour\": {\"used_percentage\": 1, \"resets_at\": \{resets_at}}}}"
    assert_true(line(json).contains("5h ○ 1% 7d"))
  }
}

///|
test "a field of the wrong type makes the input unreadable" {
  for
    json in [
      "not json", "[]", "{\"model\": \"x\"}", "{\"cost\": {\"total_lines_added\": 2.0}}",
      "{\"cwd\": 3}",
    ] {
    assert_eq(line(json), "unreadable")
  }
  assert_eq(line("null"), "🤖 Unknown │ 📊 0% │ 5h - 7d -")
}

///|
test "narrow terminals drop the later segments but keep the model" {
  let json = "{\"model\": {\"display_name\": \"日本語モデル\"}}"
  assert_eq(line(json, width=23), "🤖 日本語モデル │ 📊 0%")
  assert_eq(line(json, width=22), "🤖 日本語モデル")
  assert_eq(line(json, width=5), "🤖 日本語モデル")
}
