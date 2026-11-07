// Claude Code's Bash rules that used to grep the raw hook JSON, so a commit message quoting `terraform apply` was blocked.
// The safety rules deny when either the parsed words or the old substring match does, so they are never weaker than the grep;
// the steering rules (fd, rg, bat) are style nudges and read only the parsed leading command.

///|
/// Returns why a Bash command is denied; `require_draft` denies `gh pr create` without `--draft`, and `steer`
/// adds the fd/rg/bat nudges, which need those tools installed.
fn command_rule_denial(
  command : String,
  require_draft~ : Bool,
  steer~ : Bool = true,
) -> String? {
  let segments = @git_command.segments(command)
  if steer && steering_denial(segments) is Some(reason) {
    return Some(reason)
  }
  let parsed = parsed_denial(segments, require_draft~)
  let raw = raw_denial(command, require_draft~)
  // The draft reason wins, as it did with a pass of its own.
  match (parsed, raw) {
    (_, Some(reason)) if reason == ready_pr_reason => raw
    (Some(_), _) => parsed
    _ => raw
  }
}

///|
/// Only the leading command is redirected, as before: `rg` cannot stand in for a `grep` in a pipeline or a `$(cat <<EOF)` body.
fn steering_denial(segments : Array[Array[String]]) -> String? {
  match segments {
    [["find", ..], ..] =>
      Some(
        "Use fd instead of find! Example: fd --hidden --exclude .git --exclude node_modules --color=never --print0 <pattern>",
      )
    [["grep", ..], ..] =>
      Some(
        "Use rg instead of grep! Example: rg --no-heading --color=never --json --trim --max-columns=120 <pattern>",
      )
    [["cat", ..], ..] =>
      Some(
        "Use bat instead of cat! Example: bat --plain --paging=never --color=never <file>",
      )
    _ => None
  }
}

///|
/// The old grep hook's substrings, checked on the command text: parsing can miss quoting tricks such as
/// `"$(...)"`, backticks or `eval '...'`, but a substring cannot. `npm publish` also matches `pnpm publish`.
let raw_guarded : Array[String] = [
  "terraform apply", "terraform destroy", "npm publish", "cargo publish",
]

///|
/// Reproduces the grep rules in their order; a draft flag anywhere in the text spares `gh pr create`,
/// since the parsed rule still requires it on the command itself.
fn raw_denial(command : String, require_draft~ : Bool) -> String? {
  if require_draft &&
    command.contains("gh pr create") &&
    !has_draft_word(command) {
    return Some(ready_pr_reason)
  }
  for pattern in raw_guarded {
    if command.contains(pattern) {
      return Some(guarded_reason(pattern))
    }
  }
  None
}

///|
/// `--draft` anywhere, or `-d` as a whole word: gh's short form, which a bare substring would find in `--body-file -d.md`.
fn has_draft_word(command : String) -> Bool {
  if command.contains("--draft") {
    return true
  }
  let chars = command.to_array()
  let boundary = (c : Char) => {
    c is (' ' | '\t' | '\n' | '\'' | '"' | ';' | '&' | '|' | '(' | ')')
  }
  for i in 0..<(chars.length() - 1) {
    if chars[i] == '-' &&
      chars[i + 1] == 'd' &&
      (i == 0 || boundary(chars[i - 1])) &&
      (i + 2 == chars.length() || boundary(chars[i + 2])) {
      return true
    }
  }
  false
}

///|
fn guarded_reason(command : String) -> String {
  "\{command} is not allowed directly. Separate it from other commands and let the user approve."
}

///|
let ready_pr_reason = "gh pr create without --draft is not allowed. Always use --draft flag."

///|
fn parsed_denial(
  segments : Array[Array[String]],
  require_draft~ : Bool,
) -> String? {
  // One walk for both rules, since each walk re-parses nested scripts; it goes on past a guarded verb
  // so that the draft reason still wins wherever it appears.
  let mut found = None
  let check = (words : ArrayView[String]) => {
    if require_draft && ready_pr_denial(words) is Some(reason) {
      return Some(reason)
    }
    if found is None {
      found = guarded_denial(words)
      if !require_draft {
        return found
      }
    }
    None
  }
  match find_command(segments, depth=0, check) {
    Some(reason) => Some(reason)
    None => found
  }
}

///|
/// Tries `check` on the words from every position, so wrappers with options (`timeout 600`, `sudo -E`, `xargs`) cannot hide a program;
/// a quoted argument stays one word here, though the raw check still denies a commit message naming the command.
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
    return Some(guarded_reason("\{display(tool)} \{args[index]}"))
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
  Some(ready_pr_reason)
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
