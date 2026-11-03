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
