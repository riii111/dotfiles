// Claude Code's Bash rules that used to grep the raw hook JSON, so a commit message quoting `terraform apply` was blocked.
// They now read the parsed words of each simple command.

///|
/// Returns why a Bash command is denied; `require_draft` denies `gh pr create` without `--draft`.
fn command_rule_denial(command : String, require_draft~ : Bool) -> String? {
  let segments = @git_command.segments(command)
  // Only the leading command is redirected, as before: `rg` cannot stand in for a `grep` in a pipeline or a `$(cat <<EOF)` body.
  match segments {
    [["find", ..], ..] =>
      return Some(
        "Use fd instead of find! Example: fd --hidden --exclude .git --exclude node_modules --color=never --print0 <pattern>",
      )
    [["grep", ..], ..] =>
      return Some(
        "Use rg instead of grep! Example: rg --no-heading --color=never --json --trim --max-columns=120 <pattern>",
      )
    [["cat", ..], ..] =>
      return Some(
        "Use bat instead of cat! Example: bat --plain --paging=never --color=never <file>",
      )
    _ => ()
  }
  // One walk for both rules, since each walk re-parses nested scripts; it goes on past a guarded verb
  // so that the draft reason still wins wherever it appears.
  let mut guarded_reason = None
  let check = (words : ArrayView[String]) => {
    if require_draft && ready_pr_denial(words) is Some(reason) {
      return Some(reason)
    }
    if guarded_reason is None {
      guarded_reason = guarded_denial(words)
      if !require_draft {
        return guarded_reason
      }
    }
    None
  }
  match find_command(segments, depth=0, check) {
    Some(reason) => Some(reason)
    None => guarded_reason
  }
}

///|
/// Tries `check` on the words from every position, so wrappers with options (`timeout 600`, `sudo -E`, `xargs`) cannot hide a program;
/// a quoted argument stays one word, so a commit message naming the command does not match.
fn find_command(
  segments : Array[Array[String]],
  depth~ : Int32,
  check : (ArrayView[String]) -> String?,
) -> String? {
  for segment in segments {
    for index, _ in segment {
      let words = segment[index:]
      if check(words) is Some(reason) {
        return Some(reason)
      }
      // The depth bound only stops pathological nesting.
      if depth < 4 &&
        @shell.nested_script(words) is Some(script) &&
        find_command(@git_command.segments(script), depth=depth + 1, check)
        is Some(reason) {
        return Some(reason)
      }
    }
  }
  None
}

///|
/// The verb counts only as the subcommand, so `npm run publish` or `terraform plan -target=apply` passes.
fn guarded_denial(words : ArrayView[String]) -> String? {
  guard words is [program, .. args] else { return None }
  let tool = @shell.basename(program)
  for rule in guarded {
    let (name, verbs, options_with_value) = rule
    guard name == tool else { continue }
    // `cargo +nightly` picks a toolchain before any option.
    let args = match args {
      [toolchain, .. rest] if tool == "cargo" && toolchain.has_prefix("+") =>
        rest
      _ => args
    }
    let index = @shell.subcommand_index(args, options_with_value~)
    guard index < args.length() && verbs.contains(args[index]) else {
      return None
    }
    return Some(
      "\{display(tool)} \{args[index]} is not allowed directly. Separate it from other commands and let the user approve.",
    )
  }
  None
}

///|
/// `gh pr new` is an alias of `gh pr create`.
fn ready_pr_denial(words : ArrayView[String]) -> String? {
  guard words is [program, .. args] &&
    @shell.basename(program) == "gh" &&
    @github_comment.gh_subcommand(args) is ["pr", "create" | "new", .. args] &&
    !args
    .iter()
    .any(arg => arg == "--draft" || arg == "-d" || arg == "--draft=true") else {
    return None
  }
  Some("gh pr create without --draft is not allowed. Always use --draft flag.")
}

///|
/// Each program's verbs and the global options that take the next word; the grep rule `npm publish` also caught `pnpm publish`.
/// Terraform's only global option with a value is `-chdir=DIR`, which is one word.
let guarded : Array[(String, Array[String], Array[String])] = [
  ("terraform", ["apply", "destroy"], []),
  (
    "npm",
    ["publish"],
    [
      "--prefix", "-C", "-w", "--workspace", "--userconfig", "--globalconfig", "--cache",
      "--registry", "--loglevel", "--otp", "--tag", "--access",
    ],
  ),
  (
    "pnpm",
    ["publish"],
    ["--filter", "-F", "-C", "--dir", "--loglevel", "--reporter"],
  ),
  ("cargo", ["publish"], ["-Z", "-C", "--config", "--color"]),
]

///|
fn display(tool : String) -> String {
  if tool == "pnpm" {
    "npm"
  } else {
    tool
  }
}
