///|
async fn git_in(dir : String, args : Array[String]) -> Unit {
  let result = @git_trust.run_git(
    dir,
    [
      "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false",
      ..args,
    ],
  )
  guard result.status == 0 else { fail("git \{args[0]}: \{result.stderr}") }
}

///|
fn added(cwd : String, response : Json) -> Json {
  {
    "tool_name": "Bash",
    "cwd": cwd,
    "tool_input": { "command": "git worktree add ../wt -b wt" },
    "tool_response": response,
  }
}

///|
async test "worktree-post-add links the main worktree's ignored agent files" {
  let root = @fs.tmpdir(prefix="worktree-post-add")
  defer @fs.rmdir(root, recursive=true)
  let main = root + "/main"
  @fs.mkdir(main + "/.docs", recursive=true)
  @fs.mkdir(main + "/.claude")
  @fs.write_file(
    main + "/.gitignore",
    "CLAUDE.md\n.docs/\n.claude/settings.local.json\n",
  )
  @fs.write_file(main + "/CLAUDE.md", "rules")
  @fs.write_file(main + "/AGENTS.md", "tracked")
  @fs.write_file(main + "/.docs/plan.md", "plan")
  @fs.write_file(main + "/.claude/settings.json", "{}")
  @fs.write_file(main + "/.claude/settings.local.json", "{}")
  git_in(main, ["init", "-q"])
  git_in(main, ["add", "."])
  git_in(main, ["commit", "-qm", "init"])
  git_in(main, ["worktree", "add", "-q", "../wt", "-b", "wt"])

  // Without the line Git prints on success, nothing is linked.
  assert_eq(worktree_post_add(added(main, { "stderr": "fatal: ..." })), [])
  let linked = worktree_post_add(
    added(main, { "stderr": "Preparing worktree (new branch 'wt')" }),
  )
  assert_eq(linked, [".docs", ".claude/settings.local.json", "CLAUDE.md"])
  let wt = root + "/wt"
  for path in [".docs", ".claude/settings.local.json", "CLAUDE.md"] {
    assert_eq(@fs.kind(wt + "/" + path, follow_symlink=false), SymLink)
  }
  // Tracked files stay the worktree's own.
  assert_eq(@fs.kind(wt + "/AGENTS.md", follow_symlink=false), Regular)
  assert_eq(
    @fs.kind(wt + "/.claude/settings.json", follow_symlink=false),
    Regular,
  )
  // Running again replaces the links instead of failing on them.
  assert_eq(
    worktree_post_add(added(main, "Preparing worktree (new branch 'wt')")),
    linked,
  )
}

///|
async test "worktree-post-add ignores other commands" {
  let event : Json = {
    "tool_name": "Bash",
    "cwd": "/",
    "tool_input": { "command": "git worktree list" },
    "tool_response": "Preparing worktree",
  }
  assert_eq(worktree_post_add(event), [])
}
