// The rules flag what a script can see; whether a comment only restates the code is left to the agent that wrote it.

///|
priv enum Rule {
  LongBlock
  Parenthetical
  BrokenSentence
  Divider
  ChangeHistory
  Filler
  Duplicate
  BareTodo
  Dense
}

///|
fn Rule::label(self : Rule) -> String {
  match self {
    LongBlock => "4行以上のコメント"
    Parenthetical => "カッコ書きの注釈"
    BrokenSentence => "文の途中の改行"
    Divider => "区切り線の見出し"
    ChangeHistory => "変更履歴"
    Filler => "水増しの定型句"
    Duplicate => "同じ文の重複"
    BareTodo => "着手条件のないTODO"
    Dense => "コメントの比率が高い"
  }
}

///|
fn Rule::id(self : Rule) -> String {
  match self {
    LongBlock => "long-block"
    Parenthetical => "parenthetical"
    BrokenSentence => "broken-sentence"
    Divider => "divider"
    ChangeHistory => "change-history"
    Filler => "filler"
    Duplicate => "duplicate"
    BareTodo => "bare-todo"
    Dense => "dense"
  }
}

///|
priv struct Finding {
  rule : Rule
  path : String
  line : Int32
  text : String
}

///|
fn findings(files : Array[FileChanges]) -> Array[Finding] {
  let result = []
  let seen : Map[String, Int32] = Map([])
  for changes in files {
    for run in runs(changes.comments) {
      check_run(run, result)
    }
    for comment in changes.comments {
      check_text(comment, result)
      let key = normalized(comment.text)
      if key.length() >= 10 {
        seen[key] = seen.get(key).unwrap_or(0) + 1
      }
    }
    let count = changes.comments.length()
    if count >= dense_minimum && count * 4 >= changes.added {
      result.push({
        rule: Dense,
        path: changes.path,
        line: changes.comments[0].line,
        text: "追加\{changes.added}行のうちコメント\{count}行",
      })
    }
  }
  for changes in files {
    for comment in changes.comments {
      if seen.get(normalized(comment.text)) is Some(times) && times > 1 {
        result.push({
          rule: Duplicate,
          path: comment.path,
          line: comment.line,
          text: comment.text,
        })
      }
    }
  }
  result
}

///|
let dense_minimum : Int32 = 5

///|
/// Splits comments into runs of consecutive lines of the same kind.
fn runs(comments : Array[Comment]) -> Array[Array[Comment]] {
  let result : Array[Array[Comment]] = []
  for comment in comments {
    match result.last() {
      Some(run) if run.last().unwrap().line + 1 == comment.line &&
        same_kind(run.last().unwrap(), comment) => run.push(comment)
      _ => result.push([comment])
    }
  }
  result
}

///|
fn check_run(run : Array[Comment], result : Array[Finding]) -> Unit {
  let first = run[0]
  if first.kind is Normal && run.length() >= 4 {
    result.push({
      rule: LongBlock,
      path: first.path,
      line: first.line,
      text: "\{run.length()}行: \{first.text}",
    })
  }
  for index in 0..<(run.length() - 1) {
    let current = run[index]
    let next = run[index + 1]
    if continues(current.text, next.text) {
      result.push({
        rule: BrokenSentence,
        path: current.path,
        line: current.line,
        text: current.text,
      })
    }
  }
}

///|
let sentence_ends : String = "。．.!?！？:：;；"

///|
/// A line continues into the next when it ends mid-sentence and the next is not a list item or a new paragraph.
fn continues(current : String, next : String) -> Bool {
  guard current.length() > 0 && next.length() > 0 else { return false }
  guard current.get_char(current.length() - 1) is Some(last) &&
    !sentence_ends.contains_char(last) &&
    last != ')' &&
    last != '）' else {
    return false
  }
  !(next.has_prefix("- ") ||
  next.has_prefix("* ") ||
  next.has_prefix("|") ||
  next.has_prefix("TODO") ||
  next.get_char(0).map(Char::is_ascii_digit).unwrap_or(false) ||
  is_divider(next) ||
  is_divider(current))
}

///|
fn check_text(comment : Comment, result : Array[Finding]) -> Unit {
  let push = rule => {
    result.push({
      rule,
      path: comment.path,
      line: comment.line,
      text: comment.text,
    })
  }
  let text = comment.text
  if is_divider(text) {
    push(Divider)
  }
  if has_parenthetical(text) {
    push(Parenthetical)
  }
  let lower = text.to_lower()
  if change_history_phrases.iter().any(phrase => lower.contains(phrase)) {
    push(ChangeHistory)
  }
  if filler_phrases.iter().any(phrase => lower.contains(phrase)) {
    push(Filler)
  }
  if is_bare_todo(text) {
    push(BareTodo)
  }
}

///|
fn is_divider(text : String) -> Bool {
  divider_marks
  .iter()
  .any(mark => text.has_prefix(mark) || text.has_suffix(mark)) ||
  text.has_prefix("region") ||
  text.has_prefix("endregion") ||
  text.has_prefix("MARK:")
}

///|
let divider_marks : Array[String] = ["---", "===", "***", "###", "~~~", "___"]

///|
/// A call such as `run()` has empty parentheses; an aside has words inside them.
fn has_parenthetical(text : String) -> Bool {
  let text = without_code(text)
  if text.contains("（") && text.contains("）") {
    return true
  }
  guard text.find(" (") is Some(open) else { return false }
  guard text.view(start_offset=open + 2).find(")") is Some(close) else {
    return false
  }
  close > 0
}

///|
/// Drops `code` spans, whose parentheses belong to the code they quote.
fn without_code(text : String) -> String {
  let builder = StringBuilder()
  let mut in_code = false
  for char in text {
    if char == '`' {
      in_code = !in_code
    } else if !in_code {
      builder.write_char(char)
    }
  }
  builder.to_string()
}

///|
let change_history_phrases : Array[String] = [
  "になった", "に変更", "変更した", "以前は", "新たに", "追加した",
  "修正した", "no longer", "previously", "used to", "changed to", "changed from",
  "was added", "has been added", "anymore", "is now", "are now",
]

///|
let filler_phrases : Array[String] = [
  "ここでは", "念のため", "することが重要", "が重要です", "がポイント",
  "注意してください", "note that", "here we", "just in case", "it is important",
  "basically", "make sure to",
]

///|
let todo_markers : Array[String] = ["TODO", "FIXME", "XXX"]

///|
fn is_bare_todo(text : String) -> Bool {
  guard todo_markers.iter().find_first(marker => text.has_prefix(marker))
    is Some(marker) else {
    return false
  }
  let rest = text.view(start_offset=marker.length()).to_owned()
  let rest = match rest.find(")") {
    Some(close) if rest.has_prefix("(") =>
      rest.view(start_offset=close + 1).to_owned()
    _ => rest
  }
  @text.strip(rest.trim_start(chars=":： ")).length() < 10
}

///|
fn normalized(text : String) -> String {
  let builder = StringBuilder()
  for char in text {
    if !char.is_whitespace() {
      builder.write_char(char)
    }
  }
  builder.to_string()
}

///|
fn same_kind(left : Comment, right : Comment) -> Bool {
  match (left.kind, right.kind) {
    (Normal, Normal) | (Doc, Doc) => true
    _ => false
  }
}
