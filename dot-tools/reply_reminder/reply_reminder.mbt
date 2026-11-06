// Instructions read at session start lose effect as the conversation grows, so every prompt gets the reply rules again.
// The full rules cost several hundred characters per prompt, so they go in only after a long reply, which corrects the next one.

///|
/// Returns the reply rules to add to the prompt, given the event's transcript and the user's home.
pub async fn reminder(transcript : String, home~ : String) -> String {
  guard last_reply(read_tail(transcript)) is Some(reply) &&
    reply_length(reply) > long_reply else {
    return short_rules
  }
  let instructions = @fs.read_file(home + "/.claude/CLAUDE.md").text() catch {
    _ => return short_rules
  }
  match sections(instructions, full_sections) {
    Some(rules) => full_rules_lead + "\n\n" + rules
    None => short_rules
  }
}

///|
/// Characters of prose, without code blocks and whitespace, above which the full rules follow.
let long_reply : Int32 = 600

///|
let short_rules : String =
  #|対話の返答に限り次を守る。PR本文・資料・報告の分量はこの対象外。
  #|- 最初の1〜2文で、聞かれたことに答える
  #|- 「詳しく」と頼まれたとき以外は、調査の経緯や作業の実況を書かない
  #|- 調べれば分かることは確かめてから述べ、確かめていない推測は推測と書く
  #|- ずんだもん口調（一人称「ぼく」、文末「〜のだ」）で返す

///|
let full_rules_lead : String =
  #|直前の返答が長かった。対話の返答に限り、次の規則で書く。PR本文・資料・報告の分量はこの対象外。
  #|口調はずんだもん（一人称「ぼく」、文末「〜のだ」）を保つ。
  #|調べれば分かることは確かめてから述べ、確かめていない推測は推測と書く。

///|
let full_sections : Array[String] = ["対話", "共通の表現"]

///|
/// A transcript can grow to many megabytes, and the last reply sits at its end.
let tail_bytes : Int32 = 262144

///|
async fn read_tail(path : String) -> Array[String] {
  guard path != "" else { return [] }
  let budget = tail_bytes.to_int64()
  let (content, cut) = try {
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    let size = file.size()
    // A cut read starts one byte early, so the piece before its first LF is empty when a record begins exactly at the budget, and a cut record otherwise.
    let start = if size > budget { size - budget - 1L } else { 0L }
    let bytes = file.read_exactly_at((size - start).to_int(), position=start)
    (@utf8.decode_lossy(bytes), size > budget)
  } catch {
    _ => return []
  }
  // JSON strings can hold U+2028 and other line separators unescaped, so records split only at LF.
  let records = content.split("\n").map(record => record.to_owned()).collect()
  if cut {
    records.remove(0) |> ignore
  }
  records
}

///|
/// The text Claude wrote after its last tool call in the latest finished turn.
/// The current prompt may or may not be in the transcript yet, so a turn ending at a prompt and a trailing turn both count.
fn last_reply(lines : Array[String]) -> String? {
  let mut current = StringBuilder()
  let mut previous : String? = None
  for line in lines {
    let entry = @json.parse(line) catch { _ => continue }
    if entry is { "isSidechain": True, .. } {
      continue
    }
    match entry {
      { "type": "assistant", "message": { "content": Array(blocks), .. }, .. } =>
        for block in blocks {
          match block {
            { "type": "text", "text": String(text), .. } =>
              current.write_string(text)
            { "type": "tool_use", .. } => current = StringBuilder()
            _ => ()
          }
        }
      { "type": "user", "message": { "content": String(_), .. }, .. } => {
        let text = current.to_string()
        if text != "" {
          previous = Some(text)
        }
        current = StringBuilder()
      }
      _ => ()
    }
  }
  let text = current.to_string()
  if text != "" {
    Some(text)
  } else {
    previous
  }
}

///|
fn reply_length(reply : String) -> Int32 {
  let mut count = 0
  let mut in_code = false
  for line in @text.split_lines(reply) {
    if @text.strip(line).has_prefix("```") {
      in_code = !in_code
      continue
    }
    if !in_code {
      count += line.iter().filter(char => !char.is_whitespace()).count()
    }
  }
  count
}

///|
/// Joins the `## name` sections of a Markdown document in the given order, or `None` when one is missing.
fn sections(document : String, names : Array[String]) -> String? {
  let lines = @text.split_lines(document)
  let found = []
  for name in names {
    let heading = "## " + name
    guard lines.search(heading) is Some(start) else { return None }
    let body = [heading]
    for line in lines[start + 1:] {
      if line.has_prefix("## ") || line.has_prefix("# ") {
        break
      }
      body.push(line)
    }
    found.push(@text.strip(body.join("\n")))
  }
  Some(found.join("\n\n"))
}
