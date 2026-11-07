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
fn byte_length(value : String) -> Int32 {
  @utf8.encode(value).length()
}

///|
/// An assistant record of the given size in bytes, without its newline.
fn assistant_of_bytes(size : Int32) -> String raise {
  let record = assistant([
    text("a".repeat(size - byte_length(assistant([text("")])))),
  ])
  assert_eq(byte_length(record), size)
  record
}

///|
async fn tail_of(path : String, records : Array[String]) -> Array[String] {
  @fs.write_file(path, records.join("\n") + "\n", create_mode=CreateOrTruncate)
  read_tail(path)
}

///|
async test "read_tail keeps only the records that start inside the byte budget" {
  let dir = @fs.tmpdir(prefix="reply-reminder-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/transcript.jsonl"
  let fitting = assistant_of_bytes(tail_bytes - 1)
  assert_eq(tail_of(path, [fitting]), [fitting, ""])
  assert_eq(tail_of(path, [prompt("q"), fitting]), [fitting, ""])
  let overflowing = assistant_of_bytes(tail_bytes)
  assert_eq(tail_of(path, [prompt("q"), overflowing]), [""])
  let answer = assistant([text("answer")])
  let cut = prompt("長".repeat(tail_bytes / 3))
  assert_eq(tail_of(path, [cut, answer]), [answer, ""])
}

///|
async test "read_tail splits records only at newlines" {
  let dir = @fs.tmpdir(prefix="reply-reminder-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/transcript.jsonl"
  let reply = "a\u{2028}b\u{2029}c\u{85}d"
  let record = assistant([text(reply)])
  assert_true(record.contains(reply))
  @fs.write_file(
    path,
    prompt("q") + "\r\n" + record + "\r\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(last_reply(read_tail(path)), Some(reply))
}

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
async test "reminder quotes the length rules only after a long reply" {
  let dir = @fs.tmpdir(prefix="reply-reminder-")
  defer @fs.rmdir(dir, recursive=true)
  let transcript = dir + "/transcript.jsonl"
  async fn write(reply : String) -> Unit {
    @fs.write_file(
      transcript,
      [prompt("q"), assistant([text(reply)]), prompt("next")].join("\n") + "\n",
      create_mode=CreateOrTruncate,
    )
  }
  write("短い返答")
  assert_eq(reminder(transcript), short_rules)
  write("長".repeat(601))
  assert_eq(reminder(transcript), short_rules + "\n" + long_rules)
  assert_eq(reminder(""), short_rules)
}
