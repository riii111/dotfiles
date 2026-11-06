// Finds the repository a pull request belongs to, so its `pr.language` is read there rather than in the session's folder.
// A command names it by a pull request URL, by `--repo`, or by a `cd` before `gh`, in that order, as `gh` itself would.
// A named repository is read from its ghq checkout; without one, only the global setting applies.

///|
/// The repository a pull request belongs to: one named on a host, or the folder of a checkout.
priv enum Target {
  Repository(host~ : String, owner~ : String, repo~ : String)
  Folder(String)
}

///|
/// Returns the repository the event's pull request belongs to; `cwd` is the session's folder and `home` expands `~`.
fn target(event : Json, cwd : String, home : String) -> Target {
  let input = match event {
    { "tool_input": Object(input), .. } => input
    _ => {}
  }
  if input is { "owner": String(owner), "repo": String(repo), .. } &&
    is_name(owner) &&
    is_name(repo) {
    return Repository(host="github.com", owner~, repo~)
  }
  guard input is { "command": String(command), .. } &&
    pr_command(command) is Some((start, verb)) else {
    return Folder(cwd)
  }
  let words = gh_arguments(command.view(start_offset=start).to_owned())
  if verb == "edit" {
    for word in words.positional {
      if pull_request_url(word) is Some(found) {
        return found
      }
    }
  }
  if words.repo is Some(value) && parse_repository(value) is Some(found) {
    return found
  }
  if cd_folder(command.view(end_offset=start).to_owned(), cwd, home)
    is Some(folder) {
    return Folder(folder)
  }
  Folder(cwd)
}

///|
/// The folder whose Git configuration holds the target's `pr.language`.
/// A repository without a ghq checkout is read from `home`, which only the global and system settings apply to.
async fn language_folder(target : Target, home : String) -> String {
  match target {
    Folder(folder) => folder
    Repository(host~, owner~, repo~) => {
      let checkout = "\{home}/ghq/\{host}/\{owner}/\{repo}"
      let kind = @fs.kind(checkout) catch { _ => return home }
      if kind == Directory {
        checkout
      } else {
        home
      }
    }
  }
}

///|
/// The `--repo` value and the positional arguments of a `gh pr` command.
priv struct GhArguments {
  repo : String?
  positional : Array[String]
}

///|
/// Options of `gh pr create` and `gh pr edit` whose value is the next word.
let value_options : Array[String] = [
  "-t", "--title", "-b", "--body", "-F", "--body-file", "-B", "--base", "-H", "--head",
  "-a", "--assignee", "-l", "--label", "-m", "--milestone", "-p", "--project", "-r",
  "--reviewer", "-T", "--template", "--recover", "--add-assignee", "--remove-assignee",
  "--add-label", "--remove-label", "--add-project", "--remove-project", "--add-reviewer",
  "--remove-reviewer",
]

///|
/// Reads the arguments of the `gh pr` command at the start of `command`, up to the first control operator.
/// Heredoc bodies and option values are skipped, so a body that mentions `--repo` or a URL names nothing.
/// Arguments the shell would expand, or a command it cannot split, name nothing either.
fn gh_arguments(command : String) -> GhArguments {
  let words = @shell.split_words(
    command_lines(without_heredoc_bodies(command))[0],
    punctuation="();&|",
    comments=false,
  ) catch {
    _ => return { repo: None, positional: [], }
  }
  let mut repo = None
  let positional = []
  // The first three words are `gh pr VERB`.
  let mut index = 3
  while index < words.length() {
    let word = words[index]
    if is_control(word) {
      break
    }
    index += 1
    let value = if word == "--repo" || word == "-R" {
      let value = words.get(index)
      index += 1
      value
    } else if word.strip_prefix("--repo=") is Some(value) {
      Some(value.to_owned())
    } else if word.has_prefix("-R") && word.length() > 2 {
      let value = word.view(start_offset=2)
      Some(value.strip_prefix("=").unwrap_or(value).to_owned())
    } else {
      if value_options.contains(word) {
        index += 1
      } else if !word.has_prefix("-") && !word.contains_any(chars="$`") {
        positional.push(word)
      }
      continue
    }
    repo = match value {
      Some(value) if !value.contains_any(chars="$`") && !is_control(value) =>
        Some(value)
      _ => None
    }
  }
  { repo, positional, }
}

///|
/// Splits `command` at each newline that ends a command: one outside quotes and not escaped.
fn command_lines(command : String) -> Array[String] {
  let chars = command.to_array()
  let lines = []
  let mut start = 0
  let mut quote = None
  let mut escaped = false
  for index, char in chars {
    if escaped {
      escaped = false
      continue
    }
    match (quote, char) {
      (None, '\n') => {
        lines.push(String::from_array(chars[start:index]))
        start = index + 1
      }
      (None, '\'' | '"') => quote = Some(char)
      (None, '\\') | (Some('"'), '\\') => escaped = true
      (Some(open), _) if open == char => quote = None
      _ => ()
    }
  }
  lines.push(String::from_array(chars[start:]))
  lines
}

///|
fn is_control(word : String) -> Bool {
  word != "" && word.iter().all(char => "();&|".contains_char(char))
}

///|
/// Drops the lines of each heredoc body and its closing delimiter, keeping the rest of the command.
fn without_heredoc_bodies(command : String) -> String {
  let kept = []
  let mut delimiters : Array[String] = []
  let lines = command.split("\n").map(line => line.to_owned()).collect()
  for index, line in lines {
    if delimiters is [delimiter, ..] {
      if line.trim(chars=" \t") == delimiter {
        delimiters = delimiters[1:].to_owned()
      }
      continue
    }
    kept.push(line)
    // `<<WORD` inside quoted text opens nothing; without a closing line it is taken as such text.
    delimiters = heredoc_delimiters(line).filter(delimiter => {
      lines[index + 1:]
      .iter()
      .any(later => later.trim(chars=" \t") == delimiter)
    })
  }
  kept.join("\n")
}

///|
/// The delimiters of the heredocs a line opens, in order.
fn heredoc_delimiters(line : String) -> Array[String] {
  let delimiters = []
  let mut from = 0
  while line.view(start_offset=from).find("<<") is Some(offset) {
    let mut index = from + offset + 2
    from = index
    // `<<<` is a here-string, which has no body.
    if line.view(start_offset=index).has_prefix("<") {
      from = index + 1
      continue
    }
    if line.view(start_offset=index).has_prefix("-") {
      index += 1
    }
    while line.get_char(index) is Some(char) &&
          @shell.is_python_whitespace(char) {
      index += char.utf16_len()
    }
    if line.get_char(index) is Some('\'' | '"') {
      index += 1
    }
    let name_start = index
    while line.get_char(index) is Some(char) && @text.is_word_char(char) {
      index += char.utf16_len()
    }
    if index > name_start {
      delimiters.push(
        line.view(start_offset=name_start, end_offset=index).to_owned(),
      )
    }
  }
  delimiters
}

///|
/// Parses `OWNER/REPO`, `HOST/OWNER/REPO` or a repository URL, as `gh --repo` accepts them.
fn parse_repository(value : String) -> Target? {
  let path = strip_scheme(value).trim_end(chars="/").to_owned()
  let path = path
    .strip_suffix(".git")
    .map(view => view.to_owned())
    .unwrap_or(path)
  match path.split("/").map(part => part.to_owned()).collect() {
    [owner, repo] if is_name(owner) && is_name(repo) =>
      Some(Repository(host="github.com", owner~, repo~))
    [host, owner, repo] if is_name(host) && is_name(owner) && is_name(repo) =>
      Some(Repository(host~, owner~, repo~))
    _ => None
  }
}

///|
/// Parses `https://HOST/OWNER/REPO/pull/NUMBER`, optionally followed by a subpage.
fn pull_request_url(value : String) -> Target? {
  guard value.has_prefix("https://") || value.has_prefix("http://") else {
    return None
  }
  match strip_scheme(value).split("/").map(part => part.to_owned()).collect() {
    [host, owner, repo, "pull", number, ..] if is_name(host) &&
      is_name(owner) &&
      is_name(repo) &&
      number != "" &&
      number.iter().all(@text.is_decimal) =>
      Some(Repository(host~, owner~, repo~))
    _ => None
  }
}

///|
fn strip_scheme(value : String) -> String {
  for scheme in ["https://", "http://"] {
    if value.strip_prefix(scheme) is Some(rest) {
      return rest.to_owned()
    }
  }
  value
}

///|
fn is_name(part : String) -> Bool {
  part != "" &&
  part != "." &&
  part != ".." &&
  part
  .iter()
  .all(char => @text.is_word_char(char) || char == '.' || char == '-')
}

///|
/// Follows each `cd DIR` in the commands before `gh`, returning the folder they end in, or `None` when there is none.
/// A `cd` inside a subshell that has closed does not apply. A directory the shell would expand, other than a leading
/// `~`, makes the folder unknown.
fn cd_folder(prefix : String, cwd : String, home : String) -> String? {
  let words = @shell.split_words(
    command_lines(prefix).join(";"),
    punctuation="();&|",
    comments=false,
  ) catch {
    _ => return None
  }
  let mut folder = None
  let outer = []
  for index, word in words {
    if is_control(word) {
      for char in word {
        if char == '(' {
          outer.push(folder)
        } else if char == ')' {
          guard outer.pop() is Some(previous) else { return None }
          folder = previous
        }
      }
      continue
    }
    guard word == "cd" && (index == 0 || is_control(words[index - 1])) else {
      continue
    }
    let mut operand = index + 1
    while words.get(operand) is Some(option) && is_cd_option(option) {
      operand += 1
      if option == "--" {
        break
      }
    }
    guard words.get(operand) is Some(target) &&
      !is_control(target) &&
      target != "-" &&
      !target.contains_any(chars="$`") else {
      return None
    }
    let target = if target == "~" {
      home
    } else if target.strip_prefix("~/") is Some(rest) {
      "\{home}/\{rest}"
    } else {
      target
    }
    // A `cd` in a pipeline or in the background runs in a subprocess.
    if is_subprocess(words.get(index - 1)) ||
      is_subprocess(words.get(operand + 1)) {
      continue
    }
    let base = folder.unwrap_or(cwd)
    folder = Some(
      if target.has_prefix("/") {
        target
      } else {
        "\{base}/\{target}"
      },
    )
  }
  folder
}

///|
/// Tells whether a control operator puts the command next to it in a pipeline or in the background.
fn is_subprocess(word : String?) -> Bool {
  guard word is Some(word) && is_control(word) else { return false }
  let operator = word.trim(chars="()")
  (operator.contains("|") && operator != "||") ||
  operator == "&" ||
  operator == "|&"
}

///|
/// `--` or a group of the `-L`, `-P`, `-e` and `-@` options of `cd`.
fn is_cd_option(word : String) -> Bool {
  word == "--" ||
  (
    word.length() > 1 &&
    word.has_prefix("-") &&
    word.view(start_offset=1).iter().all(char => "LPe@".contains_char(char))
  )
}
