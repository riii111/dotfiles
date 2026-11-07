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
  if require_draft &&
    find_command(segments, depth=0, ready_pr_denial) is Some(reason) {
    return Some(reason)
  }
  find_command(segments, depth=0, guarded_denial)
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
fn guarded_denial(words : ArrayView[String]) -> String? {
  guard words is [program, .. args] else { return None }
  let tool = @shell.basename(program)
  for rule in guarded {
    let (name, verbs) = rule
    guard name == tool else { continue }
    for verb in verbs {
      if args.contains(verb) {
        return Some(
          "\{display(tool)} \{verb} is not allowed directly. Separate it from other commands and let the user approve.",
        )
      }
    }
  }
  None
}

///|
fn ready_pr_denial(words : ArrayView[String]) -> String? {
  guard words is [program, "pr", "create", .. args] &&
    @shell.basename(program) == "gh" &&
    !args
    .iter()
    .any(arg => arg == "--draft" || arg == "-d" || arg == "--draft=true") else {
    return None
  }
  Some("gh pr create without --draft is not allowed. Always use --draft flag.")
}

///|
/// The grep rule `npm publish` also caught `pnpm publish`.
let guarded : Array[(String, Array[String])] = [
  ("terraform", ["apply", "destroy"]),
  ("npm", ["publish"]),
  ("pnpm", ["publish"]),
  ("cargo", ["publish"]),
]

///|
fn display(tool : String) -> String {
  if tool == "pnpm" {
    "npm"
  } else {
    tool
  }
}
