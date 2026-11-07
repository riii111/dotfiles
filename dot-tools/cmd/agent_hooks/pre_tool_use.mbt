// One process for every PreToolUse check, where one hook per check cost a process start each on every Bash call.
// Each check still runs on the tools its own hook matched, and all of them run, so comment-review records its state as before.

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
  // Opt-in: cloud images lack fd and bat, so cloud-setup leaves these rules out as it always did.
  if bash && options.contains("--command-rules") && command is Some(command) {
    add(
      command_rule_denial(
        command,
        require_draft=options.contains("--require-draft"),
      ).map(reason => ("deny", reason)),
    )
  }
  if bash && codex {
    add(codex_policy_denial(event))
  }
  if @github_comment.is_comment_request(event) {
    add(Some(("deny", @github_comment.denial_reason)))
  }
  if bash && !codex {
    add(git_force_decision(event, options))
  }
  // Codex ran the PR checks on Bash only, and cannot ask, so its merges are denied.
  if bash || (!codex && name.has_prefix("mcp__github__")) {
    add(pr_format_decision(event, @pr_format.read_language))
    let merge_options = if codex { ["--deny-merge"] } else { options }
    add(pr_state_decision(event, merge_options, lookup))
  }
  if bash && !codex {
    add(comment_review_decision(event))
  }
  let has = (behavior : String) => {
    verdicts.iter().any(verdict => verdict.behavior == behavior)
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
async fn codex_policy_denial(event : Json) -> (String, String)? {
  guard codex_decision(event) is Some(("PreToolUse", Deny(reason))) else {
    return None
  }
  Some(("deny", reason))
}
