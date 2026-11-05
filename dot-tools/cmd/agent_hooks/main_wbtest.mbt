///|
async test "git-force-check asks, or denies with --deny-force-push" {
  let event = bash("git push -f")
  assert_eq(decision(hook_output("git-force-check", [], event)), Some("ask"))
  assert_eq(
    decision(hook_output("git-force-check", ["--deny-force-push"], event)),
    Some("deny"),
  )
}

///|
async test "github-comment-check prints a PreToolUse denial" {
  let output = hook_output(
    "github-comment-check",
    [],
    bash("gh pr comment 1 -b hi"),
  )
  let expected : Json = {
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": @github_comment.denial_reason,
    },
  }
  assert_eq(output, Some(expected))
}

///|
async test "allowed calls and events without a command print nothing" {
  assert_true(hook_output("git-force-check", [], bash("git status")) is None)
  assert_true(
    hook_output("github-comment-check", [], bash("git status")) is None,
  )
  assert_true(
    hook_output("git-force-check", [], { "tool_name": "Bash" }) is None,
  )
}

///|
async test "an unknown hook fails" {
  assert_true(
    try hook_output("git-force", [], bash("git push -f")) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
fn decision(output : Json?) -> String? {
  match output {
    Some(
      { "hookSpecificOutput": { "permissionDecision": String(value), .. }, .. }
    ) => Some(value)
    _ => None
  }
}

///|
fn bash(command : String) -> Json {
  { "tool_name": "Bash", "tool_input": { "command": command } }
}

///|
async test "permission-request answers each Codex event in its own format" {
  let event : Json = {
    "tool_input": { "command": "sudo true" },
    "cwd": "/",
    "hook_event_name": "PreToolUse",
  }
  assert_eq(
    hook_output("permission-request", [], event),
    Some({
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Privilege escalation and user switching are forbidden.",
      },
    }),
  )
  let event : Json = {
    "tool_input": { "command": "sudo true" },
    "cwd": "/",
    "hook_event_name": "PermissionRequest",
  }
  assert_eq(
    hook_output("permission-request", [], event),
    Some({
      "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": {
          "behavior": "deny",
          "message": "Privilege escalation and user switching are forbidden.",
        },
      },
    }),
  )
  assert_true(
    hook_output("permission-request", [], { "tool_input": { "command": "ls" } })
    is None,
  )
}

///|
async test "pr-footer-reset asks to send the created body again" {
  let event : Json = {
    "tool_name": "mcp__github__create_pull_request",
    "tool_input": { "body": "目的" },
  }
  guard hook_output("pr-footer-reset", [], event)
    is Some({ "decision": "block", "reason": String(reason), .. }) else {
    fail("no block")
  }
  assert_true(reason.has_suffix("上書きする。\n\n目的"))
  assert_true(
    hook_output("pr-footer-reset", [], {
      "tool_name": "mcp__github__update_pull_request",
      "tool_input": { "body": "目的" },
    })
    is None,
  )
}
