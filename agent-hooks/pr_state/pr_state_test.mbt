///|
/// Answers every lookup with `output`, or fails when it is `None`, and records the requests.
fn fake_gh(
  output : String?,
  requests : Array[@pr_state.Lookup],
) -> async (@pr_state.Lookup) -> String {
  request => {
    requests.push(request)
    guard output is Some(output) else { fail("gh failed") }
    output
  }
}

///|
fn draft(value : Bool) -> String {
  "{\"isDraft\": \{value}}"
}

///|
fn url(owner : String) -> String {
  "{\"url\": \"https://github.com/\{owner}/repo/pull/42\"}"
}

///|
async fn decide(
  command : String,
  output : String?,
  requests~ : Array[@pr_state.Lookup] = [],
  cwd~ : String = "/tmp",
) -> String? {
  let verdict = @pr_state.check(
    command,
    cwd,
    merge=Ask,
    fake_gh(output, requests),
  )
  match verdict {
    Some((Ask, _)) => Some("ask")
    Some((Deny, _)) => Some("deny")
    None => None
  }
}

///|
async test "only a draft can change its base or become a draft" {
  let commands = [
    "gh pr ready 42 --undo", "gh pr edit 42 --base main", "gh pr edit --base=main 42",
    "gh pr edit -Bmain 42", "gh pr edit 42 -B main --title 'fix: title'", "git status && gh pr ready 42 --undo",
    "gh pr view 42\ngh pr ready 42 --undo", "gh pr view 42;\ngh pr ready 42 --undo",
  ]
  for command in commands {
    assert_eq(decide(command, Some(draft(true))), None)
    assert_eq(decide(command, Some(draft(false))), Some("deny"))
  }
}

///|
async test "the lookup names the same pull request and repository" {
  let commands = [
    "gh pr edit 42 --base main -R org/repo", "gh -R org/repo pr edit --base main 42",
    "gh pr --repo org/repo edit --base main 42", "gh pr -R org/repo edit --base main 42",
    "gh pr edit --repo=org/repo --base main 42", "gh pr edit -Rorg/repo 42 -B main",
  ]
  for command in commands {
    let requests = []
    assert_eq(decide(command, Some(draft(true)), requests~), None)
    assert_eq(requests[0].args, [
      "pr", "view", "42", "--repo", "org/repo", "--json", "isDraft",
    ])
  }
  for target in ["https://github.com/org/repo/pull/42", "feature/change", ""] {
    let requests = []
    assert_eq(
      decide("gh pr ready \{target} --undo", Some(draft(true)), requests~),
      None,
    )
    let expected = if target == "" { [] } else { [target] }
    assert_eq(requests[0].args, ["pr", "view", ..expected, "--json", "isDraft"])
  }
}

///|
async test "the lookup runs where and how the command would" {
  let requests = []
  ignore(
    decide(
      "GH_REPO=org/repo gh pr ready 42 --undo",
      Some(draft(true)),
      requests~,
    ),
  )
  assert_eq(requests[0].environment.get("GH_REPO"), Some("org/repo"))

  let requests = []
  ignore(
    decide(
      "cd /nonexistent/repo && gh pr edit 42 -B main",
      Some(draft(true)),
      requests~,
    ),
  )
  assert_eq(requests[0].cwd, "/nonexistent/repo")

  let requests = []
  assert_eq(
    decide(
      "(cd /nonexistent/draft && gh pr view 1) && gh pr edit 1 -B main",
      Some(draft(false)),
      requests~,
      cwd="/tmp/open",
    ),
    Some("deny"),
  )
  assert_eq(requests[0].cwd, "/tmp/open")
}

///|
async test "redirections, comments and quoted shell characters keep the pull request" {
  let suffixes = [
    " </dev/null", " > /tmp/result", " 2>/dev/null", " >/tmp/out 2>&1", " &>/tmp/result",
    " >> /tmp/result", " # explanatory comment", " --body '(quoted) > output; # comment'",
  ]
  for suffix in suffixes {
    let requests = []
    assert_eq(
      decide("gh pr edit 1 --base main" + suffix, Some(draft(false)), requests~),
      Some("deny"),
    )
    assert_eq(requests[0].args, ["pr", "view", "1", "--json", "isDraft"])
  }
}

///|
async test "unrelated commands do not look anything up" {
  let commands = [
    "gh pr ready 42", "gh pr edit 42 --add-label bug", "git status", "echo 'gh pr ready 42 --undo'",
    "gh pr edit 42 --body 'use --base main'", "gh pr merge --help",
  ]
  let requests = []
  for command in commands {
    assert_eq(decide(command, Some(draft(false)), requests~), None)
  }
  assert_true(requests.is_empty())
}

///|
async test "an unknown draft state or a dynamic identity is denied" {
  for
    output in [
      None,
      Some("garbage"),
      Some("{}"),
      Some("{\"isDraft\": \"true\"}"),
    ] {
    assert_eq(decide("gh pr ready 42 --undo", output), Some("deny"))
  }
  let requests = []
  let commands = [
    "gh pr ready \"$PR\" --undo", "gh pr ready 42 --undo -R \"$REPO\"", "cd \"$REPO\" && gh pr edit 42 -B main",
    "cat <<EOF | gh pr edit 1 -B main\nx\nEOF", "gh pr edit 1 -B main 'unterminated",
  ]
  for command in commands {
    assert_eq(decide(command, Some(draft(true)), requests~), Some("deny"))
  }
  assert_true(requests.is_empty())
}

///|
async test "a merge asks outside personal repositories" {
  let commands = [
    "gh pr merge 42 --merge", "gh pr merge --auto --squash -R org/repo 42", "git status && gh pr merge 42 --subject 'fix: x' -b body",
  ]
  for command in commands {
    let requests = []
    assert_eq(decide(command, Some(url("sansaninc")), requests~), Some("ask"))
    assert_eq(requests[0].args[:3].to_owned(), [
      "pr",
      "view",
      requests[0].args[2],
    ])
    assert_eq(requests[0].args[requests[0].args.length() - 2:].to_owned(), [
      "--json", "url",
    ])
    assert_eq(decide(command, Some(url("riii111"))), None)
  }
  for
    output in [
      None,
      Some("garbage"),
      Some("{}"),
      Some("{\"url\": \"https://example.com/o/r/pull/1\"}"),
    ] {
    assert_eq(decide("gh pr merge 42", output), Some("ask"))
  }
  assert_eq(decide("gh pr merge \"$PR\"", Some(url("riii111"))), Some("ask"))
}

///|
async test "a merge through gh api asks outside personal repositories" {
  let requests = []
  let asking = [
    "gh api -X PUT repos/sansaninc/app/pulls/1/merge", "gh api --method=PUT /repos/sansaninc/app/pulls/1/merge -f merge_method=squash",
    "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
    "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
  ]
  for command in asking {
    assert_eq(decide(command, None, requests~), Some("ask"))
  }
  let passing = [
    "gh api -X PUT repos/riii111/app/pulls/1/merge", "gh api repos/sansaninc/app/pulls/1/merge",
    "gh api repos/sansaninc/app/pulls/1",
  ]
  for command in passing {
    assert_eq(decide(command, None, requests~), None)
  }
  assert_true(requests.is_empty())
}

///|
async test "Codex denies the merges that Claude Code asks about" {
  let verdict = @pr_state.check(
    "gh pr merge 42",
    "/tmp",
    merge=Deny,
    fake_gh(Some(url("sansaninc")), []),
  )
  assert_true(verdict is Some((Deny, _)))
}

///|
test "GitHub MCP merges ask outside personal repositories" {
  for operation in ["merge_pull_request", "enable_pr_auto_merge"] {
    let name = "mcp__github__" + operation
    assert_true(
      @pr_state.mcp_check(
        name,
        { "owner": "riii111", "pullNumber": 3 },
        merge=Ask,
      )
      is None,
    )
    assert_true(
      @pr_state.mcp_check(name, { "owner": "acme", "pullNumber": 3 }, merge=Ask)
      is Some((Ask, _)),
    )
  }
}

///|
test "GitHub MCP cannot change the base or convert to a draft" {
  let name = "mcp__github__update_pull_request"
  let inputs : Array[Json] = [{ "base": "main" }, { "draft": true }]
  for input in inputs {
    assert_true(@pr_state.mcp_check(name, input, merge=Ask) is Some((Deny, _)))
  }
  let inputs : Array[Json] = [{ "draft": false }, { "title": "fix: x" }]
  for input in inputs {
    assert_true(@pr_state.mcp_check(name, input, merge=Ask) is None)
  }
}
