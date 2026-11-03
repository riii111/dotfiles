// Claude Code and Codex treat a hook that exits 0 without output as no decision, so input that cannot be read lets the tool call through instead of blocking every call.

///|
async fn main {
  let args = @env.args()
  let hook = args.get(1).unwrap_or("")
  let options = args.iter().drop(2).collect()
  let event = @stdio.stdin.read_all().json() catch { _ => return }

  guard hook_output(hook, options, event) is Some(output) else { return }
  @stdio.stdout.write(output.stringify())
}

///|
/// Returns the PreToolUse decision to print, or `None` to let the call through.
async fn hook_output(
  hook : String,
  options : Array[String],
  event : Json,
) -> Json? {
  let decision = match hook {
    "git-force-check" => git_force_decision(event, options)
    "github-comment-check" =>
      if @github_comment.is_comment_request(event) {
        Some(("deny", @github_comment.denial_reason))
      } else {
        None
      }
    "pr-state-check" => pr_state_decision(event, options, @pr_state.run_lookup)
    "pr-format-check" => pr_format_decision(event, @pr_format.read_language)
    _ =>
      fail(
        "usage: agent-hooks git-force-check [--deny-force-push] | github-comment-check | pr-state-check [--deny-merge] | pr-format-check",
      )
  }

  guard decision is Some((behavior, reason)) else { return None }
  Some({
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": behavior,
      "permissionDecisionReason": reason,
    },
  })
}

///|
fn git_force_decision(
  event : Json,
  options : Array[String],
) -> (String, String)? {
  guard event is { "tool_input": { "command": String(command), .. }, .. } else {
    return None
  }
  let deny_force_push = options.contains("--deny-force-push")
  match @git_force.decide(command, deny_force_push~) {
    Some(Ask(reason)) => Some(("ask", reason))
    Some(Deny(reason)) => Some(("deny", reason))
    None => None
  }
}

///|
/// The working directory of the event, or of this process when the event has none.
fn event_cwd(event : Json) -> String {
  match event {
    { "cwd": String(cwd), .. } if cwd != "" => cwd
    _ => @env.current_dir().unwrap_or("")
  }
}

///|
/// Codex runs a command whose hook answers "ask", so its configuration passes `--deny-merge`.
async fn pr_state_decision(
  event : Json,
  options : Array[String],
  lookup : async (@pr_state.Lookup) -> String,
) -> (String, String)? {
  let merge : @pr_state.Decision = if options.contains("--deny-merge") {
    Deny
  } else {
    Ask
  }
  let name = match event {
    { "tool_name": String(name), .. } => name
    _ => ""
  }
  let verdict = if name.has_prefix("mcp__") {
    let input = match event {
      { "tool_input": Object(input), .. } => Json::object(input)
      _ => Json::object({})
    }
    @pr_state.mcp_check(name, input, merge~)
  } else {
    guard event is { "tool_input": { "command": String(command), .. }, .. } else {
      return None
    }
    @pr_state.check(command, event_cwd(event), merge~, lookup)
  }
  match verdict {
    Some((Ask, reason)) => Some(("ask", reason))
    Some((Deny, reason)) => Some(("deny", reason))
    None => None
  }
}

///|
/// A failure while reading the event or the configured language lets the call through, as the Python hook did.
async fn pr_format_decision(
  event : Json,
  read_language : async (String) -> String?,
) -> (String, String)? {
  let problems = @pr_format.check(event, event_cwd(event), read_language) catch {
    _ => return None
  }
  if problems.is_empty() {
    None
  } else {
    Some(("deny", @pr_format.denial_reason(problems)))
  }
}
