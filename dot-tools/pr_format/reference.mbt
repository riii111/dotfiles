///|
let closing_keywords : Array[String] = [
  "closes", "closed", "close", "fixes", "fixed", "fix", "resolves", "resolved", "resolve",
  "refs", "ref",
]

///|
/// Mirrors `^(?:(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)\s+.*#\d+|→\s)` with `re.IGNORECASE`.
fn is_reference_line(line : String) -> Bool {
  if line.has_prefix("→") {
    return line.get_char(1) is Some(char) && @shell.is_python_whitespace(char)
  }
  keyword_reference(line, closing_keywords)
}

///|
/// Mirrors `^refs?\s+.*#\d+` with `re.IGNORECASE`.
fn refs_line(line : String) -> Bool {
  keyword_reference(line, ["refs", "ref"])
}

///|
fn keyword_reference(line : String, keywords : Array[String]) -> Bool {
  let lower = line.to_lower()
  keywords
  .iter()
  .any(keyword => {
    lower.has_prefix(keyword) &&
    line.get_char(keyword.length()) is Some(char) &&
    @shell.is_python_whitespace(char) &&
    has_issue_number(line.view(start_offset=keyword.length() + 1).to_owned())
  })
}

///|
fn has_issue_number(text : String) -> Bool {
  let chars = text.iter().collect()
  for index, char in chars {
    if char == '#' &&
      chars.get(index + 1) is Some(next) &&
      @text.is_decimal(next) {
      return true
    }
  }
  false
}

///|
/// Mirrors `(?<![A-Za-z0-9&])(?:[\w.-]+/[\w.-]+)?#\d+\b|https://github\.com/[^/\s]+/[^/\s]+/(?:issues|pull)/\d+`.
fn has_reference(line : String) -> Bool {
  let chars = line.iter().collect()
  for index, char in chars {
    if char == '#' &&
      issue_number_end(chars, index + 1) &&
      reference_start(chars, index) {
      return true
    }
  }
  has_github_link(line)
}

///|
/// `\d+\b` after `#`.
fn issue_number_end(chars : Array[Char], start : Int32) -> Bool {
  let mut end = start
  while end < chars.length() && @text.is_decimal(chars[end]) {
    end += 1
  }
  end > start && !(chars.get(end) is Some(next) && @text.is_word_char(next))
}

///|
fn is_reference_neighbor(char : Char) -> Bool {
  char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '&'
}

///|
fn is_name_char(char : Char) -> Bool {
  @text.is_word_char(char) || char == '.' || char == '-'
}

///|
/// Whether a reference can start before the `#` at `hash`: right there, or at an `owner/repo` prefix.
fn reference_start(chars : Array[Char], hash : Int32) -> Bool {
  if hash == 0 || !is_reference_neighbor(chars[hash - 1]) {
    return true
  }
  let mut slash = hash
  while slash > 0 && is_name_char(chars[slash - 1]) {
    slash -= 1
  }
  guard slash < hash && slash > 0 && chars[slash - 1] == '/' else {
    return false
  }
  let slash = slash - 1
  let mut start = slash
  while start > 0 && is_name_char(chars[start - 1]) {
    start -= 1
  }
  for owner_start in start..<slash {
    if owner_start == 0 || !is_reference_neighbor(chars[owner_start - 1]) {
      return true
    }
  }
  false
}

///|
fn has_github_link(line : String) -> Bool {
  let mut from = 0
  while line.view(start_offset=from).find("https://github.com/") is Some(offset) {
    let start = from + offset + "https://github.com/".length()
    from = start
    let rest = line.view(start_offset=start).to_owned()
    let parts = rest.split("/").map(part => part.to_owned()).collect()
    guard parts is [owner, repo, kind, number, ..] else { continue }
    if is_path_part(owner) &&
      is_path_part(repo) &&
      (kind == "issues" || kind == "pull") &&
      number.get_char(0) is Some(digit) &&
      @text.is_decimal(digit) {
      return true
    }
  }
  false
}

///|
fn is_path_part(text : String) -> Bool {
  text != "" && !text.iter().any(@shell.is_python_whitespace)
}
