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
    guard @shell.assignment(token) is Some((name, value)) else { break }
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
  // Commands that read the worktree may run an fsmonitor hook or a clean/smudge filter.
  has_config("^core\\.fsmonitor$") ||
  has_config("^filter\\..*\\.(clean|smudge|process)$")
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
