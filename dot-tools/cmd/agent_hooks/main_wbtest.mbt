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
    "tool_input": { "body": "Refs #1" },
  }
  guard hook_output("pr-footer-reset", [], event)
    is Some({ "decision": "block", "reason": String(reason), .. }) else {
    fail("no block")
  }
  assert_true(reason.contains("update_pull_request"))
  assert_false(reason.contains("Refs #1"))
  assert_true(
    hook_output("pr-footer-reset", [], {
      "tool_name": "mcp__github__update_pull_request",
      "tool_input": { "body": "目的" },
    })
    is None,
  )
}

///|
async test "reply-reminder adds the reply rules to every prompt" {
  let output = hook_output("reply-reminder", [], {
    "hook_event_name": "UserPromptSubmit",
    "prompt": "hi",
  })
  guard output
    is Some(
      {
        "hookSpecificOutput": {
          "hookEventName": "UserPromptSubmit",
          "additionalContext": String(rules),
          ..
        },
        ..
      }
    ) else {
    fail("unexpected output")
  }
  assert_true(rules.has_prefix("対話の返答はCLAUDE.md"))
}

///|
async fn combined(event : Json, options : Array[String]) -> (String, String)? {
  let no_lookup : async (@pr_state.Lookup) -> String = _ => fail("no lookup")
  match pre_tool_use_output(event, options, no_lookup) {
    Some(
      {
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": String(behavior),
          "permissionDecisionReason": String(reason),
          ..
        },
        ..
      }
    ) => Some((behavior, reason))
    None => None
    _ => fail("unexpected output")
  }
}

///|
async test "pre-tool-use answers with the strongest decision of its checks" {
  assert_eq(combined(bash("ls"), []), None)
  assert_eq(combined(bash("git push -f"), []).map(pair => pair.0), Some("ask"))
  assert_eq(
    combined(bash("git push -f"), ["--deny-force-push"]).map(pair => pair.0),
    Some("deny"),
  )
  // The ask of the force push is dropped, as Claude Code ranks deny above it.
  assert_eq(
    combined(bash("git push -f && gh pr comment 1 -b hi"), []),
    Some(("deny", @github_comment.denial_reason)),
  )
  let rules = ["--steer-tools"]
  guard combined(bash("find . && gh pr comment 1 -b hi"), rules)
    is Some(("deny", reason)) else {
    fail("no denial")
  }
  assert_true(
    reason.has_prefix("Use fd") &&
    reason.has_suffix("\n\n" + @github_comment.denial_reason),
  )
  assert_eq(combined(bash("find ."), []), None)
  // The old flag name still turns the nudges on.
  assert_eq(
    combined(bash("find ."), ["--command-rules"]).map(pair => pair.0),
    Some("deny"),
  )
  assert_eq(combined(bash("git commit -m 'terraform plan'"), rules), None)
  // The safety rules need no flag, as cloud sessions pass none.
  guard combined(bash("terraform apply"), []) is Some(("deny", reason)) else {
    fail("no denial")
  }
  assert_true(reason.contains("terraform apply"))
  guard combined(bash("gh pr create --title t"), ["--require-draft"])
    is Some(("deny", reason)) else {
    fail("no denial")
  }
  assert_true(reason.contains("--draft"))
}

///|
async test "pre-tool-use runs each check on the tools its hook matched" {
  let comment : Json = {
    "tool_name": "mcp__github__add_issue_comment",
    "tool_input": { "body": "hi" },
  }
  assert_eq(
    combined(comment, []),
    Some(("deny", @github_comment.denial_reason)),
  )
  assert_eq(combined({ "tool_name": "Read", "tool_input": {} }, []), None)
  let find : Json = {
    "tool_name": "Bash",
    "tool_input": { "command": "find ." },
    "cwd": "/",
    "hook_event_name": "PreToolUse",
  }
  // Codex has no fd rule, force-push check or comment review, only its command policy.
  assert_eq(combined(find, ["--codex"]), None)
  let sudo : Json = {
    "tool_name": "Bash",
    "tool_input": { "command": "sudo true" },
    "cwd": "/",
    "hook_event_name": "PreToolUse",
  }
  assert_eq(
    combined(sudo, ["--codex"]),
    Some(("deny", "Privilege escalation and user switching are forbidden.")),
  )
}

///|
async test "pre-tool-use skips the slow checks once a cheap one denies" {
  let looked_up = Ref(false)
  let lookup : async (@pr_state.Lookup) -> String = _ => {
    looked_up.val = true
    "{\"url\": \"https://github.com/o/r/pull/1\"}"
  }
  let event = bash("gh pr comment 1 -b hi && gh pr merge 1")
  let output = pre_tool_use_output(event, [], lookup)
  guard output
    is Some({ "hookSpecificOutput": { "permissionDecision": "deny", .. }, .. }) else {
    fail("no denial")
  }
  assert_false(looked_up.val)
  // Without the cheap denial the merge is looked up.
  let _ = pre_tool_use_output(bash("gh pr merge 1"), [], lookup)
  assert_true(looked_up.val)
}

///|
async test "a slow check that fails does not drop the others' decisions" {
  let checks : Array[async () -> (String, String)?] = [
    () => fail("lookup failed"),
    () => Some(("ask", "merge")),
  ]
  assert_eq(run_slow_checks(checks), [None, Some(("ask", "merge"))])
}

///|
async test "a slow check that never returns does not drop the others' decisions" {
  let checks : Array[async () -> (String, String)?] = [
    () => {
      @async.sleep(1000000)
      Some(("deny", "late"))
    },
    () => Some(("deny", "force")),
  ]
  assert_eq(run_slow_checks(checks, deadline_ms=100), [
    None,
    Some(("deny", "force")),
  ])
}

///|
async test "a check cancelled at the deadline is reported as the deadline, not as a failure" {
  let logged : Array[String] = []
  let checks : Array[async () -> (String, String)?] = [
    () => {
      @async.sleep(1000000)
      None
    },
    // Cleanup that raises while cancelled, as a killed child process may.
    () => {
      if @async.handle_cancellation(() => @async.sleep(1000000)) is None {
        fail("killed")
      }
      None
    },
  ]
  let results = run_slow_checks(checks, deadline_ms=100, log=message => {
    logged.push(message)
  })
  assert_eq(results, [None, None])
  assert_eq(logged, ["slow checks passed the 100ms deadline"])
}
