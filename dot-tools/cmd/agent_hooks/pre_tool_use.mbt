// One process for every PreToolUse check, where one hook per check cost a process start each on every Bash call.
// Each check still runs on the tools its own hook matched. The pure checks run first, and a deny skips the slow ones,
// so a hook killed by its timeout cannot drop a deny already found. The slow ones run concurrently.

///|
priv struct Verdict {
  behavior : String
  reason : String
}

///|
/// Runs the checks of Claude Code, or of Codex with `--codex`, and answers with the strongest decision.
/// Claude Code ranks deny above ask, so a weaker decision would be dropped anyway; reasons of the same rank are joined.
async fn pre_tool_use_output(
  event : Json,
  options : Array[String],
  lookup : async (@pr_state.Lookup) -> String,
) -> Json? {
  let name = match event {
    { "tool_name": String(name), .. } => name
    _ => ""
  }
  let bash = name == "Bash"
  guard bash || name.has_prefix("mcp__") else { return None }
  let codex = options.contains("--codex")
  let verdicts : Array[Verdict] = []
  let add = (decision : (String, String)?) => {
    if decision is Some((behavior, reason)) {
      verdicts.push({ behavior, reason, })
    }
  }
  let command = match event {
    { "tool_input": { "command": String(command), .. }, .. } => Some(command)
    _ => None
  }
  // The safety rules always run for Claude Code (Codex has its own policy); the fd/rg/bat nudges are opt-in,
  // since cloud images lack fd and bat. `--command-rules` is the old name of `--steer-tools`, kept for older settings.
  if bash && !codex && command is Some(command) {
    add(
      command_rule_denial(
        command,
        require_draft=options.contains("--require-draft"),
        steer=options.contains("--steer-tools") ||
          options.contains("--command-rules"),
      ).map(reason => ("deny", reason)),
    )
  }
  if @github_comment.is_comment_request(event) {
    add(Some(("deny", @github_comment.denial_reason)))
  }
  if bash && !codex {
    add(git_force_decision(event, options))
  }
  let has = (behavior : String) => {
    verdicts.iter().any(verdict => verdict.behavior == behavior)
  }
  // The hook timeout (30s in both agents' settings) stays above the longest budget, the 10s PR lookup; run in sequence
  // they would take 22s for Claude Code (pr.language 3s, comment-review's three Git calls 3s each) and 15s for Codex (ssh -G 2s).
  // A denied call never runs, so skipping comment-review after a pure deny only defers its review to the next attempt;
  // a slow deny shows comment-review's listing too, so recording it as reviewed loses nothing.
  let slow : Array[async () -> (String, String)?] = []
  if bash && codex {
    slow.push(() => codex_policy_denial(event))
  }
  // Codex ran the PR checks on Bash only, and cannot ask, so its merges are denied.
  if bash || (!codex && name.has_prefix("mcp__github__")) {
    slow.push(() => pr_format_decision(event, @pr_format.read_language))
    let merge_options = if codex { ["--deny-merge"] } else { options }
    slow.push(() => pr_state_decision(event, merge_options, lookup))
  }
  if bash && !codex {
    slow.push(() => comment_review_decision(event))
  }
  // Separate hooks used to run these in parallel; running them together keeps that latency, and the
  // results are added in list order so the joined reasons do not depend on which finished first.
  if !has("deny") {
    run_slow_checks(slow).each(add)
  }
  let behavior = if has("deny") {
    "deny"
  } else if has("ask") {
    "ask"
  } else {
    return None
  }
  let reasons = verdicts
    .iter()
    .filter(verdict => verdict.behavior == behavior)
    .map(verdict => verdict.reason)
    .collect()
  Some(pre_tool_use_decision(behavior, reasons.join("\n\n")))
}

///|
/// Runs the checks concurrently, with the results in list order.
/// A failed check decides nothing: raised in the group, it would cancel the rest and lose a decision another one found.
/// The deadline stays under the 30s hook timeout, so a hung check (a Git lock, gh, ssh -G) is cancelled with no decision
/// instead of the hook being killed and dropping the decisions already found.
async fn run_slow_checks(
  checks : Array[async () -> (String, String)?],
  deadline_ms~ : Int32 = 20000,
) -> Array[(String, String)?] {
  let results : Array[(String, String)?] = Array::make(checks.length(), None)
  let finished = @async.with_timeout_opt(deadline_ms, () => {
    @async.with_task_group(group => {
      for index, check in checks {
        group.spawn_bg(() => {
          results[index] = check() catch {
            error => {
              log_check_failure("a check failed: \{error}")
              None
            }
          }
        })
      }
    })
  }) catch {
    _ => None
  }
  if finished is None {
    log_check_failure("slow checks passed the \{deadline_ms}ms deadline")
  }
  results
}

///|
async fn log_check_failure(message : String) -> Unit {
  @stdio.stderr.write("pre-tool-use: \{message}\n") catch {
    _ => ()
  }
}

///|
async fn codex_policy_denial(event : Json) -> (String, String)? {
  guard codex_decision(event) is Some(("PreToolUse", Deny(reason))) else {
    return None
  }
  Some(("deny", reason))
}
