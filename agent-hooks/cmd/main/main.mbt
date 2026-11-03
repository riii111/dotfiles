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
fn hook_output(
  hook : String,
  options : Array[String],
  event : Json,
) -> Json? raise {
  let decision = match hook {
    "git-force-check" => git_force_decision(event, options)
    "github-comment-check" =>
      if @github_comment.is_comment_request(event) {
        Some(("deny", @github_comment.denial_reason))
      } else {
        None
      }
    _ =>
      fail(
        "usage: agent-hooks git-force-check [--deny-force-push] | github-comment-check",
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
