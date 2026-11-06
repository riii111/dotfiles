///|
fn entry(value : Json) -> String {
  value.stringify()
}

///|
fn assistant(blocks : Array[Json]) -> String {
  entry({
    "type": "assistant",
    "message": { "role": "assistant", "content": Json::array(blocks) },
  })
}

///|
fn prompt(text : String) -> String {
  entry({
    "type": "user",
    "message": { "role": "user", "content": Json::string(text) },
  })
}

///|
fn text(value : String) -> Json {
  { "type": "text", "text": Json::string(value) }
}

///|
let tool_use : Json = { "type": "tool_use", "name": "Bash" }

///|
let tool_result : String = entry({
  "type": "user",
  "message": { "role": "user", "content": [{ "type": "tool_result" }] },
})

///|
test "last_reply takes the text after the last tool call" {
  let lines = [
    prompt("first"),
    assistant([text("checking")]),
    assistant([tool_use]),
    tool_result,
    assistant([text("answer ")]),
    assistant([text("continues")]),
  ]
  assert_eq(last_reply(lines), Some("answer continues"))
  lines.push(prompt("second"))
  assert_eq(last_reply(lines), Some("answer continues"))
}

///|
test "last_reply skips subagent entries and returns nothing without a reply" {
  let side = entry({
    "type": "assistant",
    "isSidechain": true,
    "message": { "content": [{ "type": "text", "text": "subagent" }] },
  })
  assert_eq(
    last_reply([prompt("first"), assistant([text("main")]), side]),
    Some("main"),
  )
  assert_eq(last_reply([prompt("first")]), None)
  assert_eq(last_reply(["not json"]), None)
}

///|
test "reply_length counts prose without code blocks and whitespace" {
  assert_eq(reply_length("ab c\n```\nlong code\n```\nd"), 4)
}

///|
let document : String =
  #|# Title
  #|
  #|## 対話
  #|
  #|- 短く
  #|
  #|## 作業
  #|
  #|- 進める
  #|
  #|## 共通の表現
  #|
  #|- 平易に

///|
test "sections joins the named sections in order" {
  assert_eq(
    sections(document, ["対話", "共通の表現"]),
    Some("## 対話\n\n- 短く\n\n## 共通の表現\n\n- 平易に"),
  )
  assert_eq(sections(document, ["対話", "missing"]), None)
}

///|
async test "reminder gives the full rules only after a long reply" {
  let dir = "_build/reply_reminder_test"
  @fs.mkdir(dir + "/home/.claude", recursive=true, allow_exist=true)
  @fs.write_file(
    dir + "/home/.claude/CLAUDE.md",
    document,
    create_mode=CreateOrTruncate,
  )
  let transcript = dir + "/transcript.jsonl"
  async fn write(reply : String) -> Unit {
    @fs.write_file(
      transcript,
      [prompt("q"), assistant([text(reply)]), prompt("next")].join("\n") + "\n",
      create_mode=CreateOrTruncate,
    )
  }
  write("短い返答")
  assert_eq(reminder(transcript, home=dir + "/home"), short_rules)
  write("長".repeat(601))
  let full = reminder(transcript, home=dir + "/home")
  assert_true(full.has_prefix(full_rules_lead))
  assert_true(full.contains("## 共通の表現"))
  assert_eq(reminder(transcript, home=dir + "/missing"), short_rules)
  assert_eq(reminder("", home=dir + "/home"), short_rules)
}
