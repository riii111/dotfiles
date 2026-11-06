// The command is split into the simple commands it runs so a pull request's identity comes from its own arguments.
// Shell syntax that could change what runs, such as a heredoc or an unbalanced quote, is an error, never a guess.

///|
/// Raised when the command or the pull request it names cannot be determined.
pub suberror Uncertain {
  Uncertain(String)
}

///|
priv enum Token {
  Redirect(String)
  Control(String)
  Word(String)
  Comment
}

///|
/// Splits `command` into simple commands; `(` and `)` come back as segments of their own.
pub fn segments(command : String) -> Array[Array[String]] raise Uncertain {
  let result : Array[Array[String]] = [[]]
  let mut redirect_target = false
  let mut position = 0
  while next_token(command, position) is Some((start, end, token)) {
    if !is_blank(command.view(start_offset=position, end_offset=start)) {
      raise Uncertain("unsupported shell syntax")
    }
    position = end
    match token {
      Comment => continue
      Redirect(raw) => {
        if raw.contains("<<") {
          raise Uncertain("heredoc requires a separate command")
        }
        redirect_target = true
      }
      Control(raw) => {
        if redirect_target {
          raise Uncertain("missing redirection target")
        }
        if raw == "(" || raw == ")" {
          result.push([raw])
        }
        result.push([])
      }
      Word(_) if redirect_target => redirect_target = false
      Word(raw) => {
        let words = @shell.split_words(raw, punctuation="", comments=false) catch {
          _ => raise Uncertain("ambiguous shell word")
        }
        guard words is [word] else { raise Uncertain("ambiguous shell word") }
        result.last().unwrap().push(word)
      }
    }
  }
  if !is_blank(command.view(start_offset=position)) || redirect_target {
    raise Uncertain("incomplete shell syntax")
  }
  result.filter(part => !part.is_empty())
}

///|
fn is_blank(text : StringView) -> Bool {
  text.iter().all(@shell.is_python_whitespace)
}

///|
/// Finds the next token at or after `from`, trying a redirection, a comment, a control operator and a word at each position.
fn next_token(command : String, from : Int32) -> (Int32, Int32, Token)? {
  for start in from..<command.length() {
    if redirect_end(command, start) is Some(end) {
      return Some(
        (
          start,
          end,
          Redirect(command.view(start_offset=start, end_offset=end).to_owned()),
        ),
      )
    }
    if command.code_unit_at(start) == '#' {
      let end = command
        .view(start_offset=start)
        .find("\n")
        .map(offset => start + offset)
        .unwrap_or(command.length())
      return Some((start, end, Comment))
    }
    if control_end(command, start) is Some(end) {
      return Some(
        (
          start,
          end,
          Control(command.view(start_offset=start, end_offset=end).to_owned()),
        ),
      )
    }
    if word_end(command, start) is Some(end) {
      return Some(
        (
          start,
          end,
          Word(command.view(start_offset=start, end_offset=end).to_owned()),
        ),
      )
    }
  }
  None
}

///|
let redirect_operators : Array[String] = [
  ">&", "<&", "<>", ">|", ">>", ">", "<<", "<",
]

///|
fn redirect_end(command : String, start : Int32) -> Int32? {
  let mut index = start
  while command.get_char(index) is Some(char) && @text.is_decimal(char) {
    index += char.utf16_len()
  }
  let rest = command.view(start_offset=index)
  for operator in redirect_operators {
    if rest.has_prefix(operator) {
      return Some(index + operator.length())
    }
  }
  let rest = command.view(start_offset=start)
  if rest.has_prefix("&>>") {
    Some(start + 3)
  } else if rest.has_prefix("&>") {
    Some(start + 2)
  } else {
    None
  }
}

///|
fn control_end(command : String, start : Int32) -> Int32? {
  let rest = command.view(start_offset=start)
  if rest.has_prefix("&&") || rest.has_prefix("||") {
    return Some(start + 2)
  }
  match command.code_unit_at(start) {
    ';' | '&' | '|' | '(' | ')' | '\n' => Some(start + 1)
    _ => None
  }
}

///|
/// A word is a run of plain characters, backslash escapes and complete quotes.
/// Like Python's `.`, an escape does not take a newline.
fn word_end(command : String, start : Int32) -> Int32? {
  let mut index = start
  while index < command.length() {
    let char = command.get_char(index).unwrap()
    match char {
      '\\' =>
        match command.get_char(index + 1) {
          Some(escaped) if escaped != '\n' => index += 1 + escaped.utf16_len()
          _ => break
        }
      '\'' =>
        match command.view(start_offset=index + 1).find("'") {
          Some(offset) => index += offset + 2
          None => break
        }
      '"' =>
        match double_quote_end(command, index) {
          Some(end) => index = end
          None => break
        }
      ';' | '&' | '|' | '(' | ')' | '<' | '>' => break
      _ if @shell.is_python_whitespace(char) => break
      _ => index += char.utf16_len()
    }
  }
  if index > start {
    Some(index)
  } else {
    None
  }
}

///|
fn double_quote_end(command : String, start : Int32) -> Int32? {
  let mut index = start + 1
  while command.get_char(index) is Some(char) {
    match char {
      '"' => return Some(index + 1)
      '\\' =>
        match command.get_char(index + 1) {
          Some(escaped) if escaped != '\n' => index += 1 + escaped.utf16_len()
          _ => return None
        }
      _ => index += char.utf16_len()
    }
  }
  None
}
