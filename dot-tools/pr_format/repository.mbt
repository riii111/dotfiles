// Finds the repository a pull request belongs to, so its `pr.language` is read there rather than in the session's folder.
// A command names it by `--repo`, by a `cd` before `gh`, or by a pull request URL, in that order.
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
    owner != "" &&
    repo != "" {
    return Repository(host="github.com", owner~, repo~)
  }
  guard input is { "command": String(command), .. } &&
    pr_command(command) is Some((start, verb)) else {
    return Folder(cwd)
  }
  // A heredoc holds the body, whose text must not name the repository.
  let arguments = command.view(start_offset=start).to_owned()
  let arguments = match arguments.find("<<") {
    Some(end) => arguments.view(end_offset=end).to_owned()
    None => arguments
  }
  if repo_flag(arguments) is Some(value) &&
    parse_repository(value) is Some(found) {
    return found
  }
  if cd_folder(command.view(end_offset=start).to_owned(), cwd, home)
    is Some(folder) {
    return Folder(folder)
  }
  if verb == "edit" {
    for word in @shell.split_on_whitespace(arguments) {
      if pull_request_url(unquote(word)) is Some(found) {
        return found
      }
    }
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
/// The value of `--repo`, `-R VALUE`, `-R=VALUE` or `-RVALUE`, unless the shell would change it.
fn repo_flag(arguments : String) -> String? {
  let value = match flag_value(arguments, ["--repo", "-R"]) {
    Some(value) => Some(value)
    None =>
      @shell.split_on_whitespace(arguments)
      .iter()
      .find_first(word => word.has_prefix("-R") && word.length() > 2)
      .map(word => word.view(start_offset=2).to_owned())
  }
  match value {
    Some(value) if !is_expanded_by_shell(value) => Some(unquote(value))
    _ => None
  }
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
/// A directory the shell would expand, other than a leading `~`, makes the folder unknown.
fn cd_folder(prefix : String, cwd : String, home : String) -> String? {
  let words = @shell.split_words(prefix, punctuation="();&|", comments=false) catch {
    _ => return None
  }
  let mut folder = None
  for index, word in words {
    guard word == "cd" &&
      (
        index == 0 ||
        words[index - 1].iter().all(char => "();&|".contains_char(char))
      ) else {
      continue
    }
    guard words.get(index + 1) is Some(target) &&
      !target.iter().all(char => "();&|".contains_char(char)) &&
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
