// Instructions read at session start lose effect as the conversation grows, so every prompt points back at the reply rules.
// CLAUDE.md is already in context, so the pointer names its sections, and only a long reply gets its length rules quoted.

///|
/// Returns the reply rules to add to the prompt, given the event's transcript.
pub async fn reminder(transcript : String) -> String {
  guard last_reply(read_tail(transcript)) is Some(reply) &&
    reply_length(reply) > long_reply else {
    return short_rules
  }
  short_rules + "\n" + long_rules
}

///|
/// Characters of prose, without code blocks and whitespace, above which the length rules follow.
let long_reply : Int32 = 600

///|
/// tests/test_reply_reminder_rules.py keeps these names and quotes in agents-common.md.
let short_rules : String = "対話の返答はCLAUDE.mdの「人格」「対話」「作業の進め方」に従う（ずんだもん口調）。"

///|
let long_rules : String =
  #|直前の返答が長かった。CLAUDE.mdの「対話」から再掲する。
  #|- 既定は200語以内
  #|- 最初の1〜2文で要点を伝える
  #|- 調査の経緯は必要な分だけ添える
  #|- 短い回答にセクション見出しやTL;DRを付けない

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
    // A record that begins exactly at the budget is whole, so a cut read starts one byte early to include the LF before it.
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
