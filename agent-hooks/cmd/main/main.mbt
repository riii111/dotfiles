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
  match hook {
    "permission-request" => return permission_output(event)
    "pr-footer-reset" => return pr_footer_output(event)
    "reply-reminder" => return Some(reply_reminder_output())
    _ => ()
  }
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
    "comment-review-check" => comment_review_decision(event)
    _ =>
      fail(
        "usage: agent-hooks git-force-check [--deny-force-push] | github-comment-check | pr-state-check [--deny-merge] | pr-format-check | comment-review-check | permission-request | pr-footer-reset | reply-reminder",
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

///|
async fn comment_review_decision(event : Json) -> (String, String)? {
  guard event is { "tool_input": { "command": String(command), .. }, .. } else {
    return None
  }
  let session = match event {
    { "session_id": String(id), .. } => id
    _ => ""
  }
  let home = @env.get_env_var("HOME").unwrap_or("")
  @comment_review.review(command, event_cwd(event), session~, home~).map(reason => {
    ("deny", reason)
  })
}

///|
/// Codex's command policy, for both its PreToolUse and PermissionRequest events.
async fn permission_output(event : Json) -> Json? {
  guard event
    is {
      "tool_input": { "command": String(command), .. },
      "cwd": String(cwd),
      ..
    } else {
    return None
  }
  let event_name = match event {
    { "hook_event_name": String(name), .. } => name
    _ => ""
  }
  match @permission.decide(event_name, command, cwd, @env.get_env_vars()) {
    None => None
    Some(Deny(reason)) if event_name == "PreToolUse" =>
      Some({
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": reason,
        },
      })
    Some(Deny(reason)) =>
      Some({
        "hookSpecificOutput": {
          "hookEventName": "PermissionRequest",
          "decision": { "behavior": "deny", "message": reason },
        },
      })
    Some(Allow) =>
      Some({
        "hookSpecificOutput": {
          "hookEventName": "PermissionRequest",
          "decision": { "behavior": "allow" },
        },
      })
  }
}

///|
/// In Claude Code cloud sessions the GitHub MCP server appends a `Generated by Claude Code` footer with the
/// session link on create, ignoring `attribution`; an update keeps the body as given, so Claude is told to send one.
fn pr_footer_output(event : Json) -> Json? {
  guard event
    is {
      "tool_name": String(name),
      "tool_input": { "body": String(body), .. },
      ..
    } &&
    name.has_suffix("create_pull_request") else {
    return None
  }
  Some({
    "decision": "block",
    "reason": "作成したPRの本文に、GitHub側でClaude Codeの署名とセッションのリンクが追記された。`mcp__github__update_pull_request` で、本文を次の内容に上書きする。\n\n" +
    body,
  })
}

///|
/// Instructions read at session start lose effect as the conversation grows, so Claude Code gets the reply rules on every prompt.
/// The text stays short because each prompt adds it to the history again.
fn reply_reminder_output() -> Json {
  {
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": reply_reminder,
    },
  }
}

///|
let reply_reminder : String =
  #|対話の返答に限り次を守る。PR本文・資料・報告の分量はこの対象外。
  #|- 最初の1〜2文で、聞かれたことに答える
  #|- 調査の経緯や作業の実況は書かない
  #|- 調べれば分かることは確かめてから述べ、確かめていない推測は推測と書く
  #|- ずんだもん口調（一人称「ぼく」、文末「〜のだ」）で返す
