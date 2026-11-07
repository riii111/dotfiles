// Ported from the Python hook with its parsing kept: `shlex` for words and Python's regex semantics for the
// three pattern checks, so a command the hook used to deny or allow gets the same answer.
// Deny checks go on to the compound check when the command is not a single invocation, and pass a command
// that cannot be split; the allow checks in permission.mbt instead require exact forms and fail closed.

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
