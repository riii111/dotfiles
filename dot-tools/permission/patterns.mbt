// These three checks reproduce Python regexes the hook used as a last resort on compound commands:
//   \bgit(?:\s+[^;&|]*)?\s+reset\s+[^;&|]*--hard(?:[^A-Za-z0-9_-]|$)
//   \bgit(?:\s+[^;&|]*)?\s+add\s+[^;&|]*\s-f(?:\s'\"]|$)
//   \brm\s+(?:[^;&|]*\s)?(?:-[A-Za-z]*[rR]|--recursive)
// The second ends in `\s'"]`, not a character class, so in effect it catches `-f` only at the end.

///|
fn is_space(char : Char) -> Bool {
  @shell.is_python_whitespace(char)
}

///|
fn is_operator(char : Char) -> Bool {
  char == ';' || char == '&' || char == '|'
}

///|
fn text_at(chars : Array[Char], index : Int32, text : String) -> Bool {
  guard index >= 0 && index + text.length() <= chars.length() else {
    return false
  }
  let mut offset = index
  for char in text {
    if chars[offset] != char {
      return false
    }
    offset += 1
  }
  true
}

///|
/// Python's `$` without MULTILINE: the end, or just before a final newline.
fn at_end(chars : Array[Char], index : Int32) -> Bool {
  index == chars.length() ||
  (index == chars.length() - 1 && chars[index] == '\n')
}

///|
/// The index after each occurrence of `word` that starts at a word boundary.
fn word_ends(chars : Array[Char], word : String) -> Array[Int32] {
  let ends = []
  for start in 0..<chars.length() {
    if text_at(chars, start, word) &&
      (start == 0 || !@text.is_word_char(chars[start - 1])) {
      ends.push(start + word.length())
    }
  }
  ends
}

///|
/// The end of the run of characters other than `;`, `&` and `|` that starts at `from`.
fn operator_free_end(chars : Array[Char], from : Int32) -> Int32 {
  let mut end = from
  while end < chars.length() && !is_operator(chars[end]) {
    end += 1
  }
  end
}

///|
/// For `\bgit(?:\s+[^;&|]*)?\s+NAME\s+`: the index after `NAME` and the whitespace that must follow it,
/// for each place `NAME` can stand after `git` in the same operator-free run.
fn git_subcommand_ends(
  chars : Array[Char],
  name : String,
) -> Array[(Int32, Int32)] {
  let ends = []
  for git in word_ends(chars, "git") {
    guard git < chars.length() && is_space(chars[git]) else { continue }
    let limit = operator_free_end(chars, git)
    for start in (git + 1)..<limit {
      if is_space(chars[start - 1]) &&
        text_at(chars, start, name) &&
        start + name.length() < limit &&
        is_space(chars[start + name.length()]) {
        ends.push((start + name.length(), limit))
      }
    }
  }
  ends
}

///|
fn mentions_hard_reset(chars : Array[Char]) -> Bool {
  for found in git_subcommand_ends(chars, "reset") {
    let (after, limit) = found
    for start in (after + 1)..<limit {
      guard text_at(chars, start, "--hard") && start + 6 <= limit else {
        continue
      }
      let next = start + 6
      if at_end(chars, next) ||
        (
          next < chars.length() &&
          !(chars[next].is_ascii_alphabetic() ||
          chars[next].is_ascii_digit() ||
          chars[next] == '_' ||
          chars[next] == '-')
        ) {
        return true
      }
    }
  }
  false
}

///|
fn mentions_forced_add(chars : Array[Char]) -> Bool {
  for found in git_subcommand_ends(chars, "add") {
    let (after, limit) = found
    // `add\s+` takes at least one whitespace, and `\s-f` needs another before the flag.
    for start in (after + 2)..<limit {
      guard is_space(chars[start - 1]) &&
        text_at(chars, start, "-f") &&
        start + 2 <= limit else {
        continue
      }
      let next = start + 2
      if at_end(chars, next) ||
        (
          next + 3 < chars.length() &&
          is_space(chars[next]) &&
          chars[next + 1] == '\'' &&
          chars[next + 2] == '"' &&
          chars[next + 3] == ']'
        ) {
        return true
      }
    }
  }
  false
}

///|
fn mentions_recursive_rm(chars : Array[Char]) -> Bool {
  for rm in word_ends(chars, "rm") {
    guard rm < chars.length() && is_space(chars[rm]) else { continue }
    let limit = operator_free_end(chars, rm)
    for start in (rm + 1)..<=limit {
      guard start < chars.length() && is_space(chars[start - 1]) else {
        continue
      }
      if text_at(chars, start, "--recursive") {
        return true
      }
      guard chars[start] == '-' else { continue }
      let mut index = start + 1
      while index < chars.length() && chars[index].is_ascii_alphabetic() {
        if chars[index] == 'r' || chars[index] == 'R' {
          return true
        }
        index += 1
      }
    }
  }
  false
}
