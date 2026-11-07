// Ported from the Python hook with its parsing kept: `shlex` for words and Python's regex semantics for the
// three pattern checks, so a command the hook used to deny or allow gets the same answer.
// Deny checks go on to the compound check when the command is not a single invocation, and pass a command
// that cannot be split; the allow checks in permission.mbt instead require exact forms and fail closed.

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

///|
/// Finds the Git subcommand after the global options.
fn git_command(args : ArrayView[String]) -> (String, Array[String])? {
  let index = @git_command.subcommand_index(args)
  guard index < args.length() else { return None }
  Some((args[index], args[index + 1:].to_owned()))
}

///|
/// Tells whether an assignment before the command sets anything but `GIT_PAGER=cat`.
fn has_unsafe_environment_override(words : Array[String]) -> Bool {
  for token in words {
    guard assignment(token) is Some((name, value)) else { break }
    if name != "GIT_PAGER" || value != "cat" {
      return true
    }
  }
  false
}

///|
/// Tells whether a `GIT_*` variable other than `GIT_PAGER=cat` is set, since it could redirect what Git runs.
fn has_unsafe_ambient_git_environment(
  environment : Map[String, String],
) -> Bool {
  environment
  .iter()
  .any(entry => {
    let (name, value) = entry
    name.has_prefix("GIT_") && !(name == "GIT_PAGER" && value == "cat")
  })
}

///|
fn has_external_helper_config(args : ArrayView[String]) -> Bool {
  let options = option_arguments(args)
  for index, arg in options {
    let value = if arg == "-c" && index + 1 < options.length() {
      Some(options[index + 1])
    } else if arg.has_prefix("-c") && arg.length() > 2 {
      Some(arg.view(start_offset=2).to_owned())
    } else {
      None
    }
    if value is Some(value) &&
      (
        value.has_prefix("diff.external=") ||
        (value.has_prefix("diff.") && value.contains(".command=")) ||
        value.has_prefix("filter.") ||
        value.contains(".textconv=")
      ) {
      return true
    }
  }
  false
}

///|
fn has_git_config_override(args : ArrayView[String]) -> Bool {
  let global_options = []
  let mut index = 0
  while index < args.length() &&
        args[index].has_prefix("-") &&
        args[index] != "--" {
    let option = args[index]
    global_options.push(option)
    index += 1
    if @git_command.takes_value(option) && index < args.length() {
      global_options.push(args[index])
      index += 1
    }
  }
  global_options
  .iter()
  .any(arg => {
    arg == "-c" ||
    (arg.has_prefix("-c") && !arg.has_prefix("--") && arg.length() > 2) ||
    arg == "--config-env" ||
    arg.has_prefix("--config-env=")
  })
}

///|
/// Tells whether the effective configuration runs a helper the arguments do not turn off.
async fn unsafe_git_configuration(
  subcommand : String,
  subargs : Array[String],
  has_config : async (String) -> Bool,
) -> Bool {
  if subcommand == "diff" || subcommand == "show" || subcommand == "log" {
    // gitattributes(5): `diff.<driver>.command` and `diff.external` are external diff drivers, which
    // --no-ext-diff turns off; `diff.<driver>.textconv` runs unless --no-textconv.
    if (has_config("^diff\\.external$") || has_config("^diff\\..*\\.command$")) &&
      !has_option(subargs, "--no-ext-diff") {
      return true
    }
    if has_config("^diff\\..*\\.textconv$") &&
      !has_option(subargs, "--no-textconv") {
      return true
    }
  }
  if subcommand == "fetch" || subcommand == "ls-remote" || subcommand == "push" {
    return has_config("^core\\.sshcommand$") || has_config("^core\\.gitproxy$")
  }
  false
}

///|
fn has_output_option(args : ArrayView[String]) -> Bool {
  option_arguments(args)
  .iter()
  .any(arg => {
    arg == "-o" ||
    (arg.has_prefix("-o") && !arg.has_prefix("--")) ||
    is_long_option(arg, "--output")
  })
}

///|
fn has_rebase_exec_option(args : ArrayView[String]) -> Bool {
  option_arguments(args)
  .iter()
  .any(arg => arg.has_prefix("-x") || is_long_option(arg, "--exec"))
}

///|
fn has_option(args : ArrayView[String], option : String) -> Bool {
  if option.has_prefix("--") {
    option_arguments(args).iter().any(arg => is_long_option(arg, option))
  } else {
    option_arguments(args).contains(option)
  }
}

///|
/// The shortest abbreviation Git accepts for each long option the checks look for.
let long_option_prefix_length : Map[String, Int32] = {
  "--delete": 5,
  "--discard-changes": 6,
  "--exec": 4,
  "--force": 5,
  "--force-create": 9,
  "--force-with-lease": 9,
  "--hard": 5,
  "--mirror": 5,
  "--no-index": 6,
  "--orphan": 4,
  "--output": 5,
  "--prune": 5,
  "--staged": 5,
  "--textconv": 7,
  "--update-head-ok": 8,
  "--worktree": 6,
}

///|
fn option_arguments(args : ArrayView[String]) -> ArrayView[String] {
  for index, arg in args {
    if arg == "--" {
      return args[:index]
    }
  }
  args
}

///|
fn is_long_option(arg : String, option : String) -> Bool {
  guard arg.has_prefix("--") else { return false }
  let candidate = match arg.split_once("=") {
    Some((name, _)) => name.to_owned()
    None => arg
  }
  let minimum = long_option_prefix_length.get(option).unwrap_or(option.length())
  candidate == option ||
  (candidate.length() >= minimum && option.has_prefix(candidate))
}

///|
fn has_short_flag(args : ArrayView[String], flag : Char) -> Bool {
  option_arguments(args)
  .iter()
  .any(arg => {
    arg.has_prefix("-") &&
    !arg.has_prefix("--") &&
    arg.view(start_offset=1).contains_char(flag)
  })
}

///|
fn starts_with(args : ArrayView[String], prefix : Array[String]) -> Bool {
  guard args.length() >= prefix.length() else { return false }
  for index, word in prefix {
    if args[index] != word {
      return false
    }
  }
  true
}

///|
fn prunes_now(options : ArrayView[String]) -> Bool {
  for index, arg in options {
    if is_long_option(arg, "--prune") &&
      arg.split_once("=") is Some((_, value)) &&
      value == "now" {
      return true
    }
    if arg == "--prune" &&
      index + 1 < options.length() &&
      options[index + 1] == "now" {
      return true
    }
  }
  false
}

///|
fn git_denial_reason(subcommand : String, subargs : Array[String]) -> String? {
  let force = has_option(subargs, "--force") || has_short_flag(subargs, 'f')
  let whole_tree = subargs.iter().any(arg => arg == "." || arg == ":/")
  let options = option_arguments(subargs)
  match subcommand {
    "reset" if has_option(subargs, "--hard") => Some("Hard reset is forbidden.")
    "restore" if whole_tree => {
      let staged = has_option(subargs, "--staged") ||
        has_short_flag(subargs, 'S')
      let worktree = has_option(subargs, "--worktree") ||
        has_short_flag(subargs, 'W')
      if !staged || worktree {
        Some("Restoring the entire working tree is forbidden.")
      } else {
        None
      }
    }
    "checkout" if whole_tree =>
      Some("Discarding the entire working tree is forbidden.")
    "stash" if subargs is ["clear" | "drop", ..] =>
      Some("Deleting stash entries is forbidden; leave them intact.")
    "add" if force => Some("Force-add is forbidden.")
    "clean" if force => Some("Forced clean is forbidden.")
    "gc" if prunes_now(options) =>
      Some("Immediate Git object pruning is forbidden.")
    "switch" if has_option(subargs, "--force") ||
      has_option(subargs, "--force-create") ||
      has_option(subargs, "--discard-changes") ||
      has_short_flag(subargs, 'f') ||
      has_short_flag(subargs, 'C') =>
      Some("Forced branch switching is forbidden.")
    "switch" if has_option(subargs, "--orphan") =>
      Some("Orphan branch switching is forbidden.")
    "branch" if has_short_flag(subargs, 'D') ||
      (has_option(subargs, "--delete") && force) =>
      Some("Deleting a branch is forbidden.")
    "fetch" if force ||
      has_option(subargs, "--update-head-ok") ||
      subargs.iter().any(arg => arg.has_prefix("+")) =>
      Some("Forced fetch is forbidden.")
    "push" if force ||
      has_option(subargs, "--force-with-lease") ||
      has_option(subargs, "--mirror") ||
      has_option(subargs, "--delete") ||
      has_option(subargs, "--prune") ||
      has_short_flag(subargs, 'd') ||
      subargs.iter().any(arg => arg.has_prefix("+") || arg.has_prefix(":")) =>
      Some("Destructive push is forbidden.")
    "rebase" if has_rebase_exec_option(subargs) =>
      Some("Git rebase command execution is forbidden.")
    "diff" | "show" | "log" =>
      if has_option(subargs, "--ext-diff") || has_option(subargs, "--textconv") {
        Some("External Git diff helpers are forbidden.")
      } else if has_output_option(subargs) {
        Some("Git output redirection is forbidden.")
      } else if subcommand == "diff" && has_option(subargs, "--no-index") {
        Some("Git no-index diff is forbidden.")
      } else {
        None
      }
    _ => None
  }
}

///|
/// The reason to deny `command`, checking its direct invocation first and then each Git command in a compound one.
pub async fn denial_reason(
  command : String,
  has_config : async (String) -> Bool,
) -> String? {
  words_denial_reason(command, exact_words(command), has_config)
}

///|
/// `words` is `exact_words(command)`, which the caller may reuse.
async fn words_denial_reason(
  command : String,
  words : Array[String]?,
  has_config : async (String) -> Bool,
) -> String? {
  if direct_invocation(words) is Some((executable, args)) {
    let name = @shell.basename(executable)
    let reason = match name {
      "git" => direct_git_denial_reason(words.unwrap(), args, has_config)
      _ => tool_denial_reason(name, args)
    }
    if reason is Some(_) {
      return reason
    }
  }
  compound_denial_reason(command, has_config)
}

///|
async fn direct_git_denial_reason(
  words : Array[String],
  args : Array[String],
  has_config : async (String) -> Bool,
) -> String? {
  if has_unsafe_environment_override(words) {
    return Some("Git environment overrides are forbidden.")
  }
  if has_external_helper_config(args) {
    return Some("External Git diff helpers are forbidden.")
  }
  if has_git_config_override(args) {
    return Some("Git config overrides are forbidden.")
  }
  guard git_command(args) is Some((subcommand, subargs)) else { return None }
  if unsafe_git_configuration(subcommand, subargs, has_config) {
    return Some("Unsafe Git configuration is forbidden.")
  }
  git_denial_reason(subcommand, subargs)
}

///|
fn tool_denial_reason(name : String, args : Array[String]) -> String? {
  match name {
    "gh" =>
      if starts_with(args, ["auth", "token"]) ||
        (
          starts_with(args, ["auth", "status"]) &&
          (
            has_option(args[2:], "--show-token") ||
            has_short_flag(args[2:], 't')
          )
        ) {
        Some("GitHub access-token output is forbidden.")
      } else if starts_with(args, ["repo", "delete"]) {
        Some("Repository deletion is forbidden.")
      } else if starts_with(args, ["ssh-key", "add"]) ||
        starts_with(args, ["gpg-key", "add"]) ||
        args is ["auth", "login" | "refresh" | "setup-git", ..] {
        Some("Changing persistent GitHub authentication is forbidden.")
      } else {
        None
      }
    "gcloud" =>
      if starts_with(args, ["auth", "print-access-token"]) {
        Some("Google Cloud access-token output is forbidden.")
      } else if starts_with(args, ["projects", "delete"]) {
        Some("Cloud project deletion is forbidden.")
      } else if starts_with(args, ["storage", "rm"]) ||
        starts_with(args, ["run", "jobs", "delete"]) ||
        starts_with(args, ["run", "services", "delete"]) ||
        starts_with(args, ["iam", "service-accounts", "keys", "create"]) {
        Some("Destructive cloud or credential mutation is forbidden.")
      } else {
        None
      }
    "terraform" => {
      let args = args.filter(arg => !arg.has_prefix("-chdir="))
      if args is ["apply" | "destroy" | "taint" | "import" | "force-unlock", ..] ||
        starts_with(args, ["state", "rm"]) ||
        starts_with(args, ["state", "mv"]) ||
        starts_with(args, ["workspace", "delete"]) {
        Some("Terraform state mutation is forbidden.")
      } else {
        None
      }
    }
    "sudo" | "su" =>
      Some("Privilege escalation and user switching are forbidden.")
    "chmod" if args.contains("777") =>
      Some("World-writable permissions are forbidden.")
    "rm" if has_option(args, "--recursive") ||
      has_short_flag(args, 'r') ||
      has_short_flag(args, 'R') => Some("Recursive file deletion is forbidden.")
    "find" if has_option(args, "-delete") =>
      Some("Recursive deletion through find is forbidden.")
    "chezmoi" if args is ["purge" | "destroy", ..] =>
      Some("Deleting chezmoi source or target state is forbidden.")
    "bq" if starts_with(args, ["rm"]) =>
      Some("BigQuery resource deletion is forbidden.")
    _ => None
  }
}

///|
let segment_breaks : Array[String] = [";", "&", "|", "(", ")"]

///|
/// Checks every `git` word of a compound command up to the next single `;`, `&`, `|`, `(` or `)` word.
/// A run like `&&` is one word that does not end the segment, as with `shlex`.
async fn compound_denial_reason(
  command : String,
  has_config : async (String) -> Bool,
) -> String? {
  let tokens = @shell.split_words(command, punctuation="();&|", comments=false) catch {
    _ => return None
  }
  for index, token in tokens {
    guard @shell.basename(token) == "git" else { continue }
    let segment = []
    for candidate in tokens[index + 1:] {
      if segment_breaks.contains(candidate) {
        break
      }
      segment.push(candidate)
    }
    if has_external_helper_config(segment) {
      return Some("External Git diff helpers are forbidden.")
    }
    if has_git_config_override(segment) {
      return Some("Git config overrides are forbidden.")
    }
    guard git_command(segment) is Some((subcommand, subargs)) else { continue }
    if git_denial_reason(subcommand, subargs) is Some(reason) {
      return Some(reason)
    }
    if unsafe_git_configuration(subcommand, subargs, has_config) {
      return Some("Unsafe Git configuration is forbidden.")
    }
  }
  let chars : Array[Char] = command.iter().collect()
  if mentions_hard_reset(chars) {
    return Some("Hard reset is forbidden.")
  }
  if mentions_forced_add(chars) {
    return Some("Force-add is forbidden.")
  }
  if mentions_recursive_rm(chars) {
    return Some("Recursive file deletion is forbidden.")
  }
  if tokens.iter().any(token => token.has_prefix("GIT_EXTERNAL_DIFF=")) {
    return Some("External Git diff helpers are forbidden.")
  }
  None
}
