///|
/// Removes here-document bodies and their delimiter lines, so the checks do not read the text a command is fed as commands.
/// A body with no delimiter line is kept, since `<<` may then be a shift as in `$((1<<2))`, and a missed command would pass.
/// All bodies are kept when the command names anything that could run its input, such as `bash <<EOF` or `cat <<EOF | sh`:
/// loops, groups and pipes split across lines make the receiver hard to pin down, and a kept body only risks a false deny.
pub fn strip_heredocs(command : String) -> String {
  let stripped = drop_heredoc_bodies(command)
  if stripped == command || runs_input(stripped) {
    command
  } else {
    stripped
  }
}

///|
let input_runners : Array[String] = ["eval", "xargs", "source"]

///|
/// Words that may precede `.` as the command it runs; elsewhere, as in `git add .`, it is a path.
let before_command : Array[String] = [
  "command", "builtin", "exec", "{", "!", "do", "then", "else", "elif", "time",
]

///|
/// Whether any word could execute what it reads; an unparsable command counts, to keep its bodies.
fn runs_input(command : String) -> Bool {
  let words = split_words(
    command.replace_all(old="\n", new=";"),
    punctuation=";&|()",
    comments=true,
  ) catch {
    _ => return true
  }
  let mut at_command = true
  for word in words {
    let program = basename(word)
    if shells.contains(program) ||
      input_runners.contains(program) ||
      (word == "." && at_command) {
      return true
    }
    at_command = word.iter().all(char => ";&|()".contains_char(char)) ||
      before_command.contains(word) ||
      (at_command && assignment(word) is Some(_))
  }
  false
}

///|
fn drop_heredoc_bodies(command : String) -> String {
  let chars : Array[Char] = command.iter().collect()
  let output = StringBuilder()
  let pending : Array[(String, Bool)] = []
  let mut quote : Char? = None
  let mut index = 0
  while index < chars.length() {
    let char = chars[index]
    let next = chars.get(index + 1)
    if quote is Some(open) {
      output.write_char(char)
      index += 1
      if char == open {
        quote = None
      } else if char == '\\' && open == '"' && next is Some(escaped) {
        output.write_char(escaped)
        index += 1
      }
      continue
    }
    match char {
      '\\' if next is Some(escaped) => {
        output.write_char(char)
        output.write_char(escaped)
        index += 2
      }
      '\'' | '"' => {
        quote = Some(char)
        output.write_char(char)
        index += 1
      }
      // A comment can hold an unpaired quote, as in `# don't`.
      '#' if index == 0 || is_shlex_whitespace(chars[index - 1]) =>
        while index < chars.length() && chars[index] != '\n' {
          output.write_char(chars[index])
          index += 1
        }
      '<' if next is Some('<') => {
        let end = if chars.get(index + 2) is Some('<') {
          // `<<<` passes a here-string, which has no body.
          index + 3
        } else if heredoc_delimiter(chars, index + 2)
          is Some((delimiter, tabs, end)) {
          pending.push((delimiter, tabs))
          end
        } else {
          index + 2
        }
        for position in index..<end {
          output.write_char(chars[position])
        }
        index = end
      }
      '\n' if !pending.is_empty() => {
        output.write_char(char)
        index += 1
        if heredoc_end(chars, index, pending) is Some(end) {
          index = end
        }
        pending.clear()
      }
      _ => {
        output.write_char(char)
        index += 1
      }
    }
  }
  output.to_string()
}

///|
/// Reads the delimiter word after `<<`, unquoted, and whether `<<-` strips leading tabs from the body.
fn heredoc_delimiter(
  chars : Array[Char],
  start : Int32,
) -> (String, Bool, Int32)? {
  let mut position = start
  let tabs = chars.get(position) is Some('-')
  if tabs {
    position += 1
  }
  while chars.get(position) is Some(' ' | '\t') {
    position += 1
  }
  let delimiter = StringBuilder()
  while chars.get(position) is Some(char) &&
        !is_shlex_whitespace(char) &&
        !";&|()<>".contains_char(char) {
    position += 1
    match char {
      '\'' | '"' => {
        while chars.get(position) is Some(inner) && inner != char {
          delimiter.write_char(inner)
          position += 1
        }
        guard position < chars.length() else { return None }
        position += 1
      }
      '\\' => {
        guard chars.get(position) is Some(escaped) else { return None }
        delimiter.write_char(escaped)
        position += 1
      }
      _ => delimiter.write_char(char)
    }
  }
  guard !delimiter.is_empty() else { None }
  Some((delimiter.to_string(), tabs, position))
}

///|
/// The position after the delimiter line of the last pending body, which follow one another from `start`.
fn heredoc_end(
  chars : Array[Char],
  start : Int32,
  pending : Array[(String, Bool)],
) -> Int32? {
  let mut position = start
  for heredoc in pending {
    let (delimiter, tabs) = heredoc
    while true {
      guard position < chars.length() else { return None }
      let mut line_start = position
      while position < chars.length() && chars[position] != '\n' {
        position += 1
      }
      let line_end = position
      if position < chars.length() {
        position += 1
      }
      if tabs {
        while line_start < line_end && chars[line_start] == '\t' {
          line_start += 1
        }
      }
      if String::from_array(chars[line_start:line_end]) == delimiter {
        break
      }
    }
  }
  Some(position)
}
