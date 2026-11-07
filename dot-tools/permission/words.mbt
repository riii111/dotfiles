///|
let shell_syntax_chars : String = "\n\r`<>;&|()"

///|
/// Tells whether the command has a newline, redirection, control operator, subshell or command substitution
/// outside single quotes.
pub fn has_shell_syntax(command : String) -> Bool {
  let chars : Array[Char] = command.iter().collect()
  let mut quote : Char? = None
  let mut escaped = false
  for index, char in chars {
    if escaped {
      escaped = false
      continue
    }
    let substitution = char == '$' && chars.get(index + 1) == Some('(')
    match quote {
      Some('\'') => {
        if char == '\'' {
          quote = None
        }
        continue
      }
      Some(_) => {
        if char == '"' {
          quote = None
        } else if char == '\\' {
          escaped = true
        } else if char == '`' || substitution {
          return true
        }
        continue
      }
      None => ()
    }
    if char == '\'' || char == '"' {
      quote = Some(char)
    } else if char == '\\' {
      escaped = true
    } else if shell_syntax_chars.contains_char(char) || substitution {
      return true
    }
  }
  false
}

///|
/// The words of a command without shell syntax, or `None` when it has some or cannot be split.
fn exact_words(command : String) -> Array[String]? {
  if has_shell_syntax(command) {
    return None
  }
  try @shell.split_words(command, punctuation="", comments=false) catch {
    _ => None
  } noraise {
    words => Some(words)
  }
}

///|
/// Splits a single simple command into its executable and arguments, skipping leading assignments.
pub fn direct_command(command : String) -> (String, Array[String])? {
  direct_invocation(exact_words(command))
}

///|
/// Without shell syntax, splitting at punctuation gives the same words, and a word made only of it was quoted;
/// the Python hook could not tell that from an operator, so such a command is no direct invocation.
fn direct_invocation(words : Array[String]?) -> (String, Array[String])? {
  guard words is Some(tokens) else { return None }
  let punctuation = "();&|<>"
  if tokens.is_empty() ||
    tokens
    .iter()
    .any(token => {
      token != "" && token.iter().all(char => punctuation.contains_char(char))
    }) {
    return None
  }
  let mut index = 0
  while index < tokens.length() && assignment(tokens[index]) is Some(_) {
    index += 1
  }
  guard index < tokens.length() else { return None }
  Some((tokens[index], tokens[index + 1:].to_owned()))
}

///|
/// Splits `NAME=value` when NAME is a shell variable name.
fn assignment(token : String) -> (String, String)? {
  guard token.split_once("=") is Some((name, value)) else { return None }
  let name = name.to_owned()
  guard name.get_char(0) is Some(first) &&
    (first.is_ascii_alphabetic() || first == '_') &&
    name
    .iter()
    .all(char => {
      char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_'
    }) else {
    return None
  }
  Some((name, value.to_owned()))
}
