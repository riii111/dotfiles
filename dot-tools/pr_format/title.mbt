///|
let title_types : Array[String] = [
  "feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore",
  "revert",
]

///|
/// Problems with a pull request title.
pub fn check_title(title : String) -> Array[String] {
  let problems = []
  if !is_conventional_title(title) {
    problems.push(
      "タイトルはConventional Commitsのtypeで始め、`type: 概要` の形にする",
    )
  }
  if has_mixed_space(title) {
    problems.push(
      "タイトルの日本語と英語の間にスペースを入れない",
    )
  }
  problems
}

///|
/// Mirrors `^(type)(\([^)\s]+\))?!?: \S`.
fn is_conventional_title(title : String) -> Bool {
  guard title_types.iter().find_first(kind => title.has_prefix(kind))
    is Some(kind) else {
    return false
  }
  let rest = title.view(start_offset=kind.length()).to_owned()
  let after_scope = match scope_end(rest) {
    Some(end) if colon_follows(rest.view(start_offset=end).to_owned()) => end
    _ => 0
  }
  colon_follows(rest.view(start_offset=after_scope).to_owned())
}

///|
fn scope_end(text : String) -> Int32? {
  guard text.has_prefix("(") else { return None }
  let mut index = 1
  while text.get_char(index) is Some(char) {
    if char == ')' {
      return if index > 1 { Some(index + 1) } else { None }
    }
    if @shell.is_python_whitespace(char) {
      return None
    }
    index += char.utf16_len()
  }
  None
}

///|
fn colon_follows(text : String) -> Bool {
  let text = text.strip_prefix("!").map(view => view.to_owned()).unwrap_or(text)
  guard text.strip_prefix(": ") is Some(rest) else { return false }
  rest.get_char(0) is Some(char) && !@shell.is_python_whitespace(char)
}
