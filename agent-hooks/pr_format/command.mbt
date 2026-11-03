// Reads the title and body that a `gh pr create` or `gh pr edit` command passes inline.
// The body must be written inside the command, as a heredoc or a literal, so that the rules can see it.
// Each reader mirrors the regular expression of the Python hook it replaced, including where it stops matching.

///|
/// The title and body a command sets, and whether it passes a body this check cannot read.
pub(all) struct CommandPr {
  title : String?
  body : String?
  unreadable_body : Bool
}

///|
/// Reads a `gh pr create` command, or a `gh pr edit` that sets the title or body; other commands give `None`.
pub fn read_command(command : String) -> CommandPr? {
  guard pr_command(command) is Some((start, verb)) else { return None }
  let command = command.view(start_offset=start).to_owned()
  if verb == "edit" && !has_edit_flag(command) {
    return None
  }
  let title = match flag_value(command, ["--title", "-t"]) {
    Some(value) if !is_expanded_by_shell(value) => Some(unquote(value))
    _ => None
  }
  let body = match heredoc_body(command) {
    Some(body) => Some(body)
    None =>
      match flag_value(command, ["--body", "-b"]) {
        Some(value) if !is_expanded_by_shell(value) => Some(unquote(value))
        _ => None
      }
  }
  let unreadable_body = body is None &&
    (
      flag_value(command, ["--body", "-b"]) is Some(_) ||
      flag_value(command, ["--body-file", "-F"]) is Some(_)
    )
  Some({ title, body, unreadable_body, })
}

///|
/// Finds `\bgh\s+pr\s+(create|edit)\b` and returns where it starts and its verb.
fn pr_command(command : String) -> (Int32, String)? {
  let mut from = 0
  while @text.word_at(command, "gh", from~) is Some(start) {
    from = start + 1
    guard skip_whitespace(command, start + 2) is Some(index) &&
      command.view(start_offset=index).has_prefix("pr") else {
      continue
    }
    guard skip_whitespace(command, index + 2) is Some(index) else { continue }
    for verb in ["create", "edit"] {
      if command.view(start_offset=index).has_prefix(verb) &&
        @text.is_boundary(command, index + verb.length()) {
        return Some((start, verb))
      }
    }
  }
  None
}

///|
/// Skips one or more whitespace characters at `index`, returning where they end.
fn skip_whitespace(command : String, index : Int32) -> Int32? {
  let mut end = index
  while command.get_char(end) is Some(char) && @shell.is_python_whitespace(char) {
    end += char.utf16_len()
  }
  if end > index {
    Some(end)
  } else {
    None
  }
}

///|
/// Mirrors `--title|--body|--body-file|\s-t\s|\s-b\s|\s-F\s`.
fn has_edit_flag(command : String) -> Bool {
  if command.contains("--title") || command.contains("--body") {
    return true
  }
  let chars = command.iter().collect()
  for index in 1..<(chars.length() - 2) {
    if chars[index] == '-' &&
      (
        chars[index + 1] == 't' ||
        chars[index + 1] == 'b' ||
        chars[index + 1] == 'F'
      ) &&
      @shell.is_python_whitespace(chars[index - 1]) &&
      @shell.is_python_whitespace(chars[index + 2]) {
      return true
    }
  }
  false
}

///|
/// Finds the first `(?<![\w-])(?:NAME)(?:\s+|=)VALUE` and returns its raw value.
fn flag_value(command : String, names : Array[String]) -> String? {
  for start in 0..<command.length() {
    if @text.char_before(command, start) is Some(char) &&
      (@text.is_word_char(char) || char == '-') {
      continue
    }
    for name in names {
      guard command.view(start_offset=start).has_prefix(name) else { continue }
      let after = start + name.length()
      let value_start = match skip_whitespace(command, after) {
        Some(index) => index
        None =>
          if command.view(start_offset=after).has_prefix("=") {
            after + 1
          } else {
            continue
          }
      }
      if quoted_end(command, value_start) is Some(end) {
        return Some(
          command.view(start_offset=value_start, end_offset=end).to_owned(),
        )
      }
    }
  }
  None
}

///|
/// Mirrors `"(?:[^"\\]|\\.)*"|'[^']*'|[^\s"']+` at `start`.
fn quoted_end(command : String, start : Int32) -> Int32? {
  match command.get_char(start) {
    Some('"') => {
      let mut index = start + 1
      while command.get_char(index) is Some(char) {
        match char {
          '"' => return Some(index + 1)
          '\\' =>
            match command.get_char(index + 1) {
              Some(escaped) if escaped != '\n' =>
                index += 1 + escaped.utf16_len()
              _ => return None
            }
          _ => index += char.utf16_len()
        }
      }
      None
    }
    Some('\'') =>
      command
      .view(start_offset=start + 1)
      .find("'")
      .map(offset => start + offset + 2)
    _ => {
      let mut index = start
      while command.get_char(index) is Some(char) &&
            char != '"' &&
            char != '\'' &&
            !@shell.is_python_whitespace(char) {
        index += char.utf16_len()
      }
      if index > start {
        Some(index)
      } else {
        None
      }
    }
  }
}

///|
/// Mirrors `\$[\w{(]|`` ` outside single quotes: the shell would change such a value before `gh` sees it.
fn is_expanded_by_shell(value : String) -> Bool {
  if value.has_prefix("'") {
    return false
  }
  let chars = value.iter().collect()
  for index, char in chars {
    if char == '`' {
      return true
    }
    if char == '$' &&
      chars.get(index + 1) is Some(next) &&
      (@text.is_word_char(next) || next == '{' || next == '(') {
      return true
    }
  }
  false
}

///|
fn unquote(value : String) -> String {
  let chars = value.iter().collect()
  guard chars.length() >= 2 &&
    chars[0] == chars[chars.length() - 1] &&
    (chars[0] == '"' || chars[0] == '\'') else {
    return value
  }
  let inner = String::from_array(chars[1:chars.length() - 1])
  if chars[0] == '"' {
    inner.replace_all(old="\\\"", new="\"")
  } else {
    inner
  }
}

///|
/// Mirrors `<<-?\s*(['"]?)(\w+)\1[^\n]*\n(.*?)^[ \t]*\2[ \t]*$` with `re.DOTALL | re.MULTILINE`.
fn heredoc_body(command : String) -> String? {
  let mut from = 0
  while command.view(start_offset=from).find("<<") is Some(offset) {
    let start = from + offset
    from = start + 1
    let mut index = start + 2
    if command.view(start_offset=index).has_prefix("-") {
      index += 1
    }
    while command.get_char(index) is Some(char) &&
          @shell.is_python_whitespace(char) {
      index += char.utf16_len()
    }
    let quotes = match command.get_char(index) {
      Some('\'' | '"' as quote) => [Some(quote), None]
      _ => [None]
    }
    for quote in quotes {
      let name_start = if quote is Some(_) { index + 1 } else { index }
      let mut name_end = name_start
      while command.get_char(name_end) is Some(char) && @text.is_word_char(char) {
        name_end += char.utf16_len()
      }
      // A shorter delimiter is tried when the longest one has no closing line, as the regex backtracks.
      while name_end > name_start {
        let name = command
          .view(start_offset=name_start, end_offset=name_end)
          .to_owned()
        if heredoc_after_name(command, name_end, quote, name) is Some(body) {
          return Some(body)
        }
        name_end -= @text.char_before(command, name_end).unwrap().utf16_len()
      }
    }
  }
  None
}

///|
fn heredoc_after_name(
  command : String,
  name_end : Int32,
  quote : Char?,
  name : String,
) -> String? {
  let mut index = name_end
  if quote is Some(quote) {
    guard command.get_char(index) is Some(char) && char == quote else {
      return None
    }
    index += 1
  }
  guard command.view(start_offset=index).find("\n") is Some(offset) else {
    return None
  }
  let body_start = index + offset + 1
  let mut line_start = body_start
  while line_start <= command.length() {
    let line_end = match command.view(start_offset=line_start).find("\n") {
      Some(offset) => line_start + offset
      None => command.length()
    }
    let line = command.view(start_offset=line_start, end_offset=line_end)
    if line.trim(chars=" \t") == name {
      return Some(
        command.view(start_offset=body_start, end_offset=line_start).to_owned(),
      )
    }
    line_start = line_end + 1
  }
  None
}
