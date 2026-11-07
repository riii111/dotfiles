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
  if require_draft && segments.iter().any(creates_ready_pr) {
    return Some(
      "gh pr create without --draft is not allowed. Always use --draft flag.",
    )
  }
  guarded_denial(segments, depth=0)
}

///|
/// Matches a guarded program at any word, so wrappers with options (`timeout 600`, `sudo -E`, `xargs`) cannot hide it;
/// a quoted argument stays one word, so a commit message naming the command does not match.
fn guarded_denial(segments : Array[Array[String]], depth~ : Int32) -> String? {
  for segment in segments {
    for index, word in segment {
      let tool = @shell.basename(word)
      for rule in guarded {
        let (name, verbs) = rule
        guard name == tool else { continue }
        for verb in verbs {
          if segment[index + 1:].contains(verb) {
            return Some(
              "\{display(tool)} \{verb} is not allowed directly. Separate it from other commands and let the user approve.",
            )
          }
        }
      }
      // The depth bound only stops pathological nesting.
      if depth < 4 &&
        shell_command(segment[index:]) is Some(script) &&
        guarded_denial(@git_command.segments(script), depth=depth + 1)
        is Some(reason) {
        return Some(reason)
      }
    }
  }
  None
}

///|
let shells : Array[String] = ["sh", "bash", "zsh", "dash", "ksh"]

///|
/// The script of `sh -c SCRIPT`, also with combined options like `-lc` or `-ec`.
fn shell_command(words : ArrayView[String]) -> String? {
  guard words is [program, .. args] && shells.contains(@shell.basename(program)) else {
    return None
  }
  let mut inline = false
  for arg in args {
    if arg.has_prefix("-") && !arg.has_prefix("--") && arg.length() > 1 {
      inline = inline || arg.contains_char('c')
    } else if arg.has_prefix("--") {
      continue
    } else {
      return if inline { Some(arg) } else { None }
    }
  }
  None
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

///|
let wrappers : Array[String] = [
  "env", "command", "exec", "sudo", "nohup", "time",
]

///|
/// The basename of the program a simple command runs, past assignments and wrappers, with its index.
fn command_word(segment : Array[String]) -> (String, Int32)? {
  for index, word in segment {
    if wrappers.contains(word) || @shell.assignment(word) is Some(_) {
      continue
    }
    return Some((@shell.basename(word), index))
  }
  None
}

///|
fn creates_ready_pr(segment : Array[String]) -> Bool {
  guard command_word(segment) is Some(("gh", index)) &&
    segment[index + 1:] is ["pr", "create", .. args] else {
    return false
  }
  !args
  .iter()
  .any(arg => arg == "--draft" || arg == "-d" || arg == "--draft=true")
}
