///|
test "denies comment posting commands" {
  let commands = [
    "gh pr comment 1 --body hi", "gh pr review 1 --comment -b hi", "/opt/homebrew/bin/gh -R owner/repo pr comment 1 -b hi",
    "GH_HOST=github.com gh pr comment 1 -b hi", "git status && gh pr comment 1 --body-file draft.md",
    "gh pr view 1\ngh pr comment 1 -b hi", "bash -lc 'gh pr comment 1 -b hi'", "gh pr close 1 --comment hi",
    "gh api repos/a/b/issues/1/comments -f body=hi", "gh api -X POST repos/a/b/pulls/1/comments --input draft.json",
    "gh api repos/a/b/pulls/1/comments/2/replies -f body=hi", "gh api --method PATCH repos/a/b/issues/comments/2 -f body=hi",
    "gh api -XPOST repos/a/b/pulls/1/reviews/2/events -f event=COMMENT", "gh api graphql -f 'query=mutation { addComment(input: {}) { clientMutationId } }'",
  ]
  for command in commands {
    assert_true(@github_comment.is_comment_request(bash(command)), msg=command)
  }
}

///|
test "allows reads and unrelated commands" {
  let commands = [
    "gh pr view 1 --json title,body", "gh-loupe pr show 1", "gh api repos/a/b/issues/1/comments",
    "gh api -X GET repos/a/b/pulls/1/comments -f per_page=100", "gh api -X DELETE repos/a/b/pulls/1/reviews/2",
    "gh api graphql -f 'query={ repository(owner: \"a\", name: \"b\") { name } }'",
    "gh pr create --draft --title 'fix: title' --body hi", "gh issue comment 1 -b hi",
    "gh issue close 1 --comment hi", "rg 'gh pr comment' tests", "echo gh pr comment 1",
  ]
  for command in commands {
    assert_false(@github_comment.is_comment_request(bash(command)), msg=command)
  }
}

///|
test "denies GitHub connector comment tools" {
  let operations = [
    "add_comment_to_issue", "add_review_to_pr", "reply_to_review_comment", "update_issue_comment",
    "update_review_comment", "add_issue_comment", "add_comment_to_pending_review",
    "add_reply_to_pull_request_comment", "pull_request_review_write", "resolve_review_thread",
  ]
  for operation in operations {
    assert_true(
      @github_comment.is_comment_request({
        "tool_name": "mcp__codex_apps__github_\{operation}",
      }),
      msg=operation,
    )
  }
  let names = [
    "mcp__codex_apps__github_fetch_pr_comments", "mcp__codex_apps__github_create_pull_request",
    "mcp__codex_app__send_message_to_thread",
  ]
  for name in names {
    assert_false(
      @github_comment.is_comment_request({
        "tool_name": name,
        "tool_input": { "body": "hi" },
      }),
      msg=name,
    )
  }
}

///|
test "denies GitHub MCP comment tools" {
  let operations = [
    "add_issue_comment", "add_comment_to_pending_review", "add_reply_to_pull_request_comment",
    "pull_request_review_write", "resolve_review_thread",
  ]
  for operation in operations {
    assert_true(
      @github_comment.is_comment_request({
        "tool_name": "mcp__github__\{operation}",
      }),
      msg=operation,
    )
  }
  let names = [
    "mcp__github__pull_request_read", "mcp__github__create_pull_request", "mcp__github__issue_write",
  ]
  for name in names {
    assert_false(
      @github_comment.is_comment_request({
        "tool_name": name,
        "tool_input": { "body": "hi" },
      }),
      msg=name,
    )
  }
}

///|
test "falls back to whitespace splitting on unbalanced quotes" {
  assert_true(
    @github_comment.is_comment_request(bash("gh pr comment 1 -b 'unclosed")),
  )
}

///|
test "skips a prefix assignment whose name has non-ASCII characters" {
  // zsh runs `gh` after such an assignment.
  assert_true(
    @github_comment.is_comment_request(bash("FÖO=1 gh pr comment 1 -b hi")),
  )
}

///|
fn bash(command : String) -> Json {
  { "tool_name": "Bash", "tool_input": { "command": command } }
}
