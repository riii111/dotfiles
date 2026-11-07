// Codex calls this policy for PreToolUse, which can only deny, and for PermissionRequest, which can also
// approve a narrow set of exact commands in a trusted checkout without asking.

///|
pub(all) enum Decision {
  Allow
  Deny(String)
}

///|
/// Decides a Bash command for the Codex hook event `event_name`; `None` leaves it to Codex.
/// `environment` is the hook's own environment, whose `GIT_*` variables the approved commands inherit.
pub async fn decide(
  event_name : String,
  command : String,
  cwd : String,
  environment : Map[String, String],
) -> Decision? {
  let has_config = git_config_probe(cwd)
  if denial_reason(command, has_config) is Some(reason) {
    return Some(Deny(reason))
  }
  guard event_name == "PermissionRequest" else { return None }
  let home = environment.get("HOME").unwrap_or("")
  if is_safe_auth_status(command) ||
    is_task_dispatch_lock_release(command, home) ||
    safe_git_request(command, cwd, environment, has_config) ||
    safe_push(command, cwd, environment, has_config) {
    Some(Allow)
  } else {
    None
  }
}

///|
/// Tells whether the effective Git configuration in `cwd` has a key matching a pattern; a failed lookup counts as a match.
/// Answers are kept for the probe's lifetime, so a probe must not outlive one decision.
fn git_config_probe(cwd : String) -> async (String) -> Bool {
  let answers : Map[String, Bool] = Map([])
  async fn(pattern) {
    if answers.is_empty() {
      // One Git start answers every pattern the policy asks, instead of one per pattern.
      let keys = configured_keys(cwd, combined_pattern)
      for known in config_patterns {
        let (name, matches) = known
        answers[name] = match keys {
          Some(keys) => keys.iter().any(matches)
          None => true
        }
      }
    }
    if answers.get(pattern) is Some(answer) {
      return answer
    }
    let answer = match configured_keys(cwd, pattern) {
      Some(keys) => !keys.is_empty()
      None => true
    }
    answers[pattern] = answer
    answer
  }
}

///|
/// The patterns the policy asks, with a matcher for the keys Git prints, whose section and variable are lowercased.
let config_patterns : Array[(String, (String) -> Bool)] = [
  ("^diff\\.external$", key => key == "diff.external"),
  (
    "^filter\\..*\\.textconv$",
    key => {
      key.length() >= "filter..textconv".length() &&
      key.has_prefix("filter.") &&
      key.has_suffix(".textconv")
    },
  ),
  ("^core\\.sshcommand$", key => key == "core.sshcommand"),
  ("^core\\.gitproxy$", key => key == "core.gitproxy"),
]

///|
let combined_pattern : String = "^(diff\\.external|filter\\..*\\.textconv|core\\.sshcommand|core\\.gitproxy)$"

///|
/// The keys set in `cwd` that match `pattern`, or `None` when Git fails.
async fn configured_keys(cwd : String, pattern : String) -> Array[String]? {
  let result = @git_trust.run_git(cwd, [
    "config", "--null", "--get-regexp", pattern,
  ]) catch {
    _ => return None
  }
  if result.status != 0 && result.status != 1 {
    return None
  }
  // With --null each entry is the key, a newline and the value, ended by NUL.
  Some(
    result.stdout
    .split("\u{0}")
    .filter(entry => entry != "")
    .map(entry => {
      match entry.split_once("\n") {
        Some((key, _)) => key.to_owned()
        None => entry.to_owned()
      }
    })
    .collect(),
  )
}

///|
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
fn is_safe_auth_status(command : String) -> Bool {
  exact_words(command) is Some(["gh", "auth", "status"])
}

///|
/// Unattended task-dispatch runs must release their lock without anyone to approve.
fn is_task_dispatch_lock_release(command : String, home : String) -> Bool {
  let home = home.trim_end(chars="/").to_owned()
  let lock = home + "/agent-desk/.lock"
  match exact_words(command) {
    Some(["rm", path]) => path == lock + "/started_at"
    Some(["rmdir", path]) => path == lock
    _ => false
  }
}

///|
let allowed_git_subcommands : Array[String] = [
  "status", "diff", "log", "show", "rev-parse", "ls-files", "switch", "add", "commit",
  "merge", "rebase", "cherry-pick",
]

///|
let listing_branch_options : Array[String] = [
  "--show-current", "--list", "-a", "-r", "--all", "--remotes",
]

///|
async fn safe_git_request(
  command : String,
  cwd : String,
  environment : Map[String, String],
  has_config : async (String) -> Bool,
) -> Bool {
  guard direct_command(command) is Some(("git", args)) else { return false }
  if has_unsafe_environment_override(command) ||
    has_unsafe_ambient_git_environment(environment) ||
    has_git_config_override(args) {
    return false
  }
  guard git_invocation(args, cwd) is Some((target, subcommand, subargs)) else {
    return false
  }
  let allowed = match (subcommand, subargs) {
    ("branch", []) => true
    ("branch", [option]) => listing_branch_options.contains(option)
    ("fetch" | "ls-remote", ["origin"]) => true
    (name, _) => allowed_git_subcommands.contains(name)
  }
  // The denial check already read the configuration of `cwd`, which is the usual target.
  let same_dir = target == cwd ||
    (@fs.realpath(cwd) catch { _ => "" }) == target
  let target_config = if same_dir {
    has_config
  } else {
    git_config_probe(target)
  }
  allowed &&
  git_denial_reason(subcommand, subargs) is None &&
  !unsafe_git_arguments(subcommand, subargs, target) &&
  !unsafe_git_configuration(subcommand, subargs, target_config) &&
  @git_trust.trusted_repository(target, ignore_case=true) is Some(_)
}

///|
/// Resolves the repository a Git command runs in when its only global options are `--no-pager` and `-C`.
/// A `-C` path that does not exist fails here, where Python's lenient resolve could still reach a directory.
async fn git_invocation(
  args : Array[String],
  cwd : String,
) -> (String, String, Array[String])? {
  let mut target = cwd
  let mut index = 0
  while index < args.length() && args[index].has_prefix("-") {
    let option = args[index]
    if option == "--no-pager" {
      index += 1
      continue
    }
    let path = if option == "-C" {
      guard index + 1 < args.length() else { return None }
      index += 2
      args[index - 1]
    } else if option.has_prefix("-C") && option.length() > 2 {
      index += 1
      option.view(start_offset=2).to_owned()
    } else {
      return None
    }
    target = if path.has_prefix("/") { path } else { target + "/" + path }
  }
  guard index < args.length() else { return None }
  let resolved = @fs.realpath(target) catch { _ => return None }
  let kind = @fs.kind(resolved) catch { _ => return None }
  guard kind == Directory else { return None }
  Some((resolved, args[index], args[index + 1:].to_owned()))
}

///|
async fn unsafe_git_arguments(
  subcommand : String,
  subargs : Array[String],
  cwd : String,
) -> Bool {
  guard subcommand == "diff" || subcommand == "show" || subcommand == "log" else {
    return false
  }
  if subargs.iter().any(arg => arg.has_prefix("/")) {
    return true
  }
  for index, arg in subargs {
    if arg == "--" {
      let paths = subargs[index + 1:]
      guard !paths.is_empty() else { return false }
      // The worktree root is the same for every path, so Git is asked once.
      guard worktree_root(cwd) is Some((root, base)) else { return true }
      for path in paths {
        if path.has_prefix("/") {
          return true
        }
        let resolved = resolve_leniently(base, path)
        if resolved != root && !resolved.has_prefix(root + "/") {
          return true
        }
      }
      return false
    }
  }
  false
}

///|
/// The resolved worktree root and the resolved `cwd`.
async fn worktree_root(cwd : String) -> (String, String)? {
  let result = @git_trust.run_git(cwd, ["rev-parse", "--show-toplevel"]) catch {
    _ => return None
  }
  guard result.status == 0 else { return None }
  let root = @fs.realpath(result.stdout.trim()) catch { _ => return None }
  let base = @fs.realpath(cwd) catch { _ => return None }
  Some((root, base))
}

///|
/// Resolves `relative` below the resolved `base` part by part, like Python's non-strict `Path.resolve`:
/// an existing part has its symlinks resolved, and a missing part is kept as written.
async fn resolve_leniently(base : String, relative : String) -> String {
  let mut path = base
  for part in relative.split("/") {
    match part {
      "" | "." => continue
      ".." =>
        path = match path.rev_split_once("/") {
          Some((parent, _)) if parent != "" => parent.to_owned()
          _ => "/"
        }
      _ => {
        let candidate = if path == "/" {
          "/" + part.to_owned()
        } else {
          path + "/" + part.to_owned()
        }
        path = @fs.realpath(candidate) catch { _ => candidate }
      }
    }
  }
  path
}

///|
let protected_branches : Array[String] = ["main", "master"]

///|
async fn safe_push(
  command : String,
  cwd : String,
  environment : Map[String, String],
  has_config : async (String) -> Bool,
) -> Bool {
  guard exact_words(command)
    is Some(
      ["git", "push", "origin", "HEAD"]
      | ["git", "push", "-u" | "--set-upstream", "origin", "HEAD"]
    ) else {
    return false
  }
  if has_unsafe_ambient_git_environment(environment) {
    return false
  }
  guard current_branch(cwd) is Some(branch) &&
    !protected_branches.contains(branch) else {
    return false
  }
  guard @git_trust.trusted_repository(cwd, ignore_case=true) is Some(_) else {
    return false
  }
  !unsafe_git_configuration("push", ["origin", "HEAD"], has_config)
}

///|
async fn current_branch(cwd : String) -> String? {
  let result = @git_trust.run_git(cwd, ["branch", "--show-current"]) catch {
    _ => return None
  }
  guard result.status == 0 else { return None }
  let branch = result.stdout.trim().to_owned()
  if branch == "" {
    None
  } else {
    Some(branch)
  }
}
