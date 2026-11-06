// Commands are matched by their parsed words, so requests that scripts build at runtime or read from files are not recognized.
// Issue comments stay available through `gh issue`, but the API and the connectors share the PR and Issue comment endpoints, so both stay denied there.
// Resolving a review thread is denied with them, since it answers the reviewer as a reply would.

///|
pub let denial_reason : String = "GitHub comment posting is forbidden. Return the draft in chat."

///|
/// Reports whether a PreToolUse event posts a GitHub comment through a shell command or a GitHub MCP tool.
pub fn is_comment_request(event : Json) -> Bool {
  guard event is Object(fields) else { return false }
  let name = match fields.get("tool_name") {
    Some(String(name)) => name
    _ => ""
  }
  if name.has_prefix("mcp__") {
    return @github_tool.operation(name) is Some(operation) &&
      comment_tools.contains(operation)
  }

  match fields.get("tool_input") {
    Some(Object(input)) =>
      match input.get("command") {
        Some(String(command)) => posts_comment(command)
        _ => false
      }
    _ => false
  }
}

///|
/// Operations of the Codex GitHub connector and of the GitHub MCP server that Claude Code cloud sessions use, which publish comment text or resolve threads.
let comment_tools : Array[String] = [
  "add_comment_to_issue", "add_review_to_pr", "reply_to_review_comment", "update_issue_comment",
  "update_review_comment", "add_issue_comment", "add_comment_to_pending_review",
  "add_reply_to_pull_request_comment", "pull_request_review_write", "resolve_review_thread",
]

///|
fn posts_comment(command : String) -> Bool {
  segments(command).iter().any(words => is_comment_invocation(words))
}

///|
/// Splits a command into the words of each simple command, as the Python hook split on runs of `();<>|&` characters.
fn segments(command : String) -> Array[Array[String]] {
  let words = @shell.split_words(
    command.replace_all(old="\n", new=";"),
    punctuation="();<>|&",
    comments=false,
  ) catch {
    _ => @shell.split_on_whitespace(command)
  }

  let segments = [[]]
  for word in words {
    // An empty quoted word also counts as a separator, matching the previous hook.
    if word.iter().all(char => "();<>|&".contains_char(char)) {
      segments.push([])
    } else {
      segments.last().unwrap().push(word)
    }
  }
  segments
}

///|
let shells : Array[String] = ["bash", "sh", "zsh"]

///|
let command_prefixes : Array[String] = ["env", "command", "exec"]

///|
fn is_comment_invocation(words : Array[String]) -> Bool {
  let mut start = 0
  while start < words.length() &&
        (is_assignment(words[start]) || command_prefixes.contains(words[start])) {
    start += 1
  }
  guard start < words.length() else { return false }

  let executable = basename(words[start])
  let args = words[start + 1:]
  if shells.contains(executable) &&
    args.length() >= 2 &&
    args[0].has_prefix("-") &&
    args[0].contains_char('c') {
    return posts_comment(args[1])
  }
  guard executable == "gh" else { return false }

  let mut first = 0
  while first < args.length() && args[first] is ("-R" | "--repo" | "--hostname") {
    first += 2
  }
  let args = if first < args.length() { args[first:] } else { [][:] }
  is_gh_comment(args)
}

///|
fn is_gh_comment(args : ArrayView[String]) -> Bool {
  match args {
    ["pr", "comment" | "review", ..] => true
    ["pr", "close" | "reopen", .. rest] =>
      rest
      .iter()
      .any(arg => arg is ("-c" | "--comment") || arg.has_prefix("--comment="))
    ["api", ..] => {
      let request = args.join(" ")
      (has_comment_endpoint(request) || has_comment_mutation(request)) &&
      is_api_write(args)
    }
    _ => false
  }
}

///|
fn is_api_write(args : ArrayView[String]) -> Bool {
  let mut http_method = ""
  let mut has_fields = false
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    index += 1
    if arg is ("-X" | "--method") {
      http_method = if index < args.length() { args[index] } else { "" }
      index += 1
    } else if arg.has_prefix("--method=") {
      http_method = arg.view(start_offset=9).to_owned()
    } else if arg.has_prefix("-X") {
      http_method = arg.view(start_offset=2).to_owned()
    } else if field_options.iter().any(option => arg.has_prefix(option)) {
      has_fields = true
    }
  }

  // gh api sends fields as a POST body unless another method is given.
  if http_method.is_empty() {
    http_method = if has_fields { "POST" } else { "GET" }
  }
  http_method.to_upper() is ("POST" | "PATCH" | "PUT")
}

///|
let field_options : Array[String] = [
  "-f", "-F", "--field", "--raw-field", "--input",
]

///|
/// Matches `repos/<owner>/<repo>/(issues|pulls)/[<number>/](comments|reviews)` followed by a word boundary.
fn has_comment_endpoint(request : String) -> Bool {
  let chars : Array[Char] = request.iter().collect()
  for start in 0..<chars.length() {
    guard match_text(chars, start, "repos/") is Some(position) else { continue }
    guard skip_path_segment(chars, position) is Some(position) else { continue }
    guard skip_path_segment(chars, position) is Some(position) else { continue }
    guard match_any(chars, position, ["issues/", "pulls/"]) is Some(position) else {
      continue
    }

    let after_number = match skip_while(chars, position, Char::is_ascii_digit) {
      end if end > position => match_text(chars, end, "/")
      _ => None
    }
    for candidate in [after_number, Some(position)] {
      guard candidate is Some(candidate) else { continue }
      if match_any(chars, candidate, ["comments", "reviews"]) is Some(end) &&
        !is_word_at(chars, end) {
        return true
      }
    }
  }
  false
}

///|
let comment_mutations : Array[(String, Bool)] = [
  ("addComment", false),
  ("updateIssueComment", false),
  ("addPullRequestReview", true),
  ("submitPullRequestReview", false),
  ("updatePullRequestReview", true),
]

///|
/// Matches a GraphQL mutation name at a word boundary followed by `(`; the flagged names also match with any word suffix.
fn has_comment_mutation(request : String) -> Bool {
  let chars : Array[Char] = request.iter().collect()
  for start in 0..<chars.length() {
    if start > 0 && is_word_at(chars, start - 1) {
      continue
    }
    for mutation in comment_mutations {
      let (name, allows_suffix) = mutation
      guard match_text(chars, start, name) is Some(end) else { continue }

      let end = if allows_suffix {
        skip_while(chars, end, is_word_char)
      } else {
        end
      }
      let end = skip_while(chars, end, @shell.is_python_whitespace)
      if end < chars.length() && chars[end] == '(' {
        return true
      }
    }
  }
  false
}

///|
/// Treats any non-ASCII character as part of the name, since Python's `\w` is Unicode and zsh accepts such names in a prefix assignment.
fn is_assignment(word : String) -> Bool {
  guard word.iter().head() is Some(first) &&
    (first.is_ascii_alphabetic() || first == '_') else {
    return false
  }
  for char in word.iter().drop(1) {
    if char == '=' {
      return true
    }
    if !is_word_char(char) && char.is_ascii() {
      return false
    }
  }
  false
}

///|
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(index) => path.view(start_offset=index + 1).to_owned()
    None => path
  }
}

///|
fn skip_path_segment(chars : Array[Char], start : Int32) -> Int32? {
  let end = skip_while(chars, start, char => {
    char != '/' && !@shell.is_python_whitespace(char)
  })
  guard end > start && end < chars.length() && chars[end] == '/' else { None }
  Some(end + 1)
}

///|
fn match_any(
  chars : Array[Char],
  start : Int32,
  texts : Array[String],
) -> Int32? {
  for text in texts {
    if match_text(chars, start, text) is Some(end) {
      return Some(end)
    }
  }
  None
}

///|
fn match_text(chars : Array[Char], start : Int32, text : String) -> Int32? {
  let mut position = start
  for char in text {
    guard position < chars.length() && chars[position] == char else {
      return None
    }
    position += 1
  }
  Some(position)
}

///|
fn skip_while(
  chars : Array[Char],
  start : Int32,
  predicate : (Char) -> Bool,
) -> Int32 {
  let mut position = start
  while position < chars.length() && predicate(chars[position]) {
    position += 1
  }
  position
}

///|
fn is_word_at(chars : Array[Char], position : Int32) -> Bool {
  position < chars.length() && is_word_char(chars[position])
}

///|
/// Covers ASCII only, unlike Python's Unicode `\w`, so a non-ASCII neighbor of a matched name counts as a word boundary and errs toward denying.
fn is_word_char(char : Char) -> Bool {
  char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_'
}
