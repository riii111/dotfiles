///|
/// Raised for input that Python's `shlex` rejects with `ValueError`.
pub suberror ShellSyntaxError {
  UnclosedQuote
  DanglingEscape
}

///|
/// Splits a command the way Python's `shlex.shlex` does in POSIX mode with `whitespace_split` enabled.
/// The hooks keep the tokenization of their Python predecessors, so a `#` comment and runs of punctuation follow `shlex`, not the shell grammar.
pub fn split_words(
  command : String,
  punctuation~ : String,
  comments~ : Bool,
) -> Array[String] raise ShellSyntaxError {
  let lexer = Lexer::new(command, punctuation, comments)
  let words = []
  while lexer.read_word() is Some(word) {
    words.push(word)
  }
  words
}

///|
/// Splits on runs of whitespace like Python's `str.split()` without arguments.
pub fn split_on_whitespace(text : String) -> Array[String] {
  let words = []
  let word = StringBuilder()
  for char in text {
    if is_python_whitespace(char) {
      if !word.is_empty() {
        words.push(word.to_string())
        word.reset()
      }
    } else {
      word.write_char(char)
    }
  }
  if !word.is_empty() {
    words.push(word.to_string())
  }
  words
}

///|
/// The part of a command word after its last `/`, which names the program it runs.
pub fn basename(path : String) -> String {
  match path.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => path
  }
}

///|
/// Matches Python's `str.isspace()`, which `str.split()` and the `\s` regex class use.
pub fn is_python_whitespace(char : Char) -> Bool {
  match char.to_int() {
    0x09..<=0x0D | 0x1C..<=0x20 | 0x85 | 0xA0 | 0x1680 => true
    0x2000..<=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 => true
    _ => false
  }
}

///|
priv enum State {
  Between
  Word
  Punctuation
  Quoted(Char)
  Escaped(Char?)
  Finished
}

///|
priv struct Lexer {
  chars : Array[Char]
  punctuation : String
  comments : Bool
  mut position : Int32
  mut pushback : Char?
  mut state : State
}

///|
fn Lexer::new(command : String, punctuation : String, comments : Bool) -> Lexer {
  {
    chars: command.iter().collect(),
    punctuation,
    comments,
    position: 0,
    pushback: None,
    state: Between,
  }
}

///|
fn Lexer::read_word(self : Lexer) -> String? raise ShellSyntaxError {
  let word = StringBuilder()
  let mut quoted = false
  while true {
    let next = self.read_char()
    match self.state {
      Finished => break
      Between =>
        match next {
          None => {
            self.state = Finished
            break
          }
          Some(char) if is_shlex_whitespace(char) => continue
          Some('#') if self.comments => self.skip_line()
          Some('\\') => self.state = Escaped(None)
          Some(char) if self.punctuation.contains_char(char) => {
            word.write_char(char)
            self.state = Punctuation
          }
          Some('\'' | '"' as quote) => self.state = Quoted(quote)
          Some(char) => {
            word.write_char(char)
            self.state = Word
          }
        }
      Quoted(quote) => {
        quoted = true
        match next {
          None => raise UnclosedQuote
          Some(char) if char == quote => self.state = Word
          Some('\\') if quote == '"' => self.state = Escaped(Some(quote))
          Some(char) => word.write_char(char)
        }
      }
      Escaped(quote) => {
        guard next is Some(char) else { raise DanglingEscape }
        // Inside double quotes, POSIX keeps the backslash unless it escapes the quote or itself.
        if quote is Some(quote) && char != '\\' && char != quote {
          word.write_char('\\')
        }
        word.write_char(char)
        self.state = match quote {
          Some(quote) => Quoted(quote)
          None => Word
        }
      }
      Word | Punctuation =>
        match next {
          None => {
            self.state = Finished
            break
          }
          Some(char) if is_shlex_whitespace(char) => {
            self.state = Between
            if !word.is_empty() || quoted {
              break
            }
          }
          Some('#') if self.comments => {
            self.skip_line()
            self.state = Between
            if !word.is_empty() || quoted {
              break
            }
          }
          Some(char) if self.state is Punctuation => {
            if self.punctuation.contains_char(char) {
              word.write_char(char)
              continue
            }
            self.pushback = Some(char)
            self.state = Between
            break
          }
          Some('\'' | '"' as quote) => self.state = Quoted(quote)
          Some('\\') => self.state = Escaped(None)
          Some(char) if self.punctuation.contains_char(char) => {
            self.pushback = Some(char)
            self.state = Between
            if !word.is_empty() || quoted {
              break
            }
          }
          Some(char) => word.write_char(char)
        }
    }
  }

  if word.is_empty() && !quoted {
    None
  } else {
    Some(word.to_string())
  }
}

///|
fn Lexer::read_char(self : Lexer) -> Char? {
  if self.pushback is Some(char) {
    self.pushback = None
    return Some(char)
  }
  guard self.position < self.chars.length() else { None }
  let char = self.chars[self.position]
  self.position += 1
  Some(char)
}

///|
/// Drops the rest of the line including its newline, as `shlex` reads a comment with `readline()`.
fn Lexer::skip_line(self : Lexer) -> Unit {
  while self.position < self.chars.length() {
    let char = self.chars[self.position]
    self.position += 1
    if char == '\n' {
      break
    }
  }
}

///|
fn is_shlex_whitespace(char : Char) -> Bool {
  char is (' ' | '\t' | '\r' | '\n')
}
