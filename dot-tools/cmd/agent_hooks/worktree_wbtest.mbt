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

///|
async test "worktree-post-add targets the added path, not the last listed worktree" {
  let root = @fs.tmpdir(prefix="worktree-post-add-order")
  defer @fs.rmdir(root, recursive=true)
  let main = root + "/main"
  @fs.mkdir(main, recursive=true)
  @fs.write_file(main + "/.gitignore", ".docs/\n")
  @fs.mkdir(main + "/.docs")
  @fs.write_file(main + "/.docs/plan.md", "plan")
  git_in(main, ["init", "-q"])
  git_in(main, ["add", "."])
  git_in(main, ["commit", "-qm", "init"])
  // Git lists linked worktrees by path, so these come after the new one.
  for name in ["yankee", "zeta"] {
    git_in(main, ["worktree", "add", "-q", "../" + name, "-b", name])
    @fs.mkdir(root + "/" + name + "/.docs")
    @fs.write_file(root + "/" + name + "/.docs/own.md", "own")
  }
  git_in(main, ["worktree", "add", "-q", "-b", "alpha", "../alpha", "HEAD"])
  let event : Json = {
    "tool_name": "Bash",
    "cwd": main,
    "tool_input": { "command": "git worktree add -b alpha ../alpha HEAD" },
    "tool_response": "Preparing worktree (new branch 'alpha')",
  }
  assert_eq(worktree_post_add(event), [".docs"])
  assert_eq(@fs.kind(root + "/alpha/.docs", follow_symlink=false), SymLink)
  for name in ["yankee", "zeta"] {
    assert_eq(@fs.exists(root + "/" + name + "/.docs/own.md"), true)
  }
}

///|
test "worktree_add_path reads the path past options with values" {
  let cases : Array[(String, (String, String)?)] = [
    ("git worktree add ../wt", Some((".", "./../wt"))),
    ("git worktree add -b wt ../wt main", Some((".", "./../wt"))),
    ("git worktree add -fbwt ../wt", Some((".", "./../wt"))),
    ("git worktree add --lock --reason why ../wt", Some((".", "./../wt"))),
    ("git worktree add --reason=why -B wt -- ../wt", Some((".", "./../wt"))),
    ("git worktree add --orphan -b wt ../wt", Some((".", "./../wt"))),
    ("git worktree add /abs/wt", Some((".", "/abs/wt"))),
    ("git -C repo worktree add -q ../wt", Some(("./repo", "./repo/../wt"))),
    // Git applies each -C to the directory of the ones before it, and an absolute one resets it.
    ("git -C a -C b worktree add wt", Some(("./a/b", "./a/b/wt"))),
    ("git -C a -C /abs worktree add wt", Some(("/abs", "/abs/wt"))),
    ("git worktree add -b wt", None),
    ("git worktree list", None),
    ("echo git worktree add ../wt", None),
    // The shell expands these before Git sees the path.
    ("git worktree add ~/wt/x", Some((".", "/h/wt/x"))),
    ("git worktree add ~", Some((".", "/h"))),
    ("git worktree add $HOME/wt/x", Some((".", "/h/wt/x"))),
    ("git -C repo worktree add ${HOME}/wt", Some(("./repo", "/h/wt"))),
    ("git -C repo worktree add \"$PWD/../x\"", Some(("./repo", "./../x"))),
    ("git worktree add ~other/wt", Some((".", "./~other/wt"))),
    ("git worktree add \"$(pwd)/../x\"", Some((".", "./$(pwd)/../x"))),
    // A later segment counts, run from where the `cd` before it moved the shell.
    (
      "cd repo && git worktree add ../x -b feat",
      Some(("./repo", "./repo/../x")),
    ),
    ("cd a; cd b && git -C c worktree add wt", Some(("./a/b/c", "./a/b/c/wt"))),
    ("cd ~/repo && git worktree add $PWD/x", Some(("/h/repo", "/h/repo/x"))),
    ("git status && git worktree add wt", Some((".", "./wt"))),
    ("cd repo && echo git worktree add wt", None),
  ]
  for case in cases {
    let (command, expected) = case
    assert_eq(worktree_add_path(command, ".", home="/h"), expected)
  }
}

///|
/// Sets a worktree's creation time, as Git records it, to `when`, in `touch -d` form.
async fn age_worktree(main : String, name : String, when : String) -> Unit {
  let (status, _, _) = @process.collect_output("touch", [
    "-d",
    when,
    main + "/.git/worktrees/" + name + "/commondir",
  ])
  guard status == 0 else { fail("touch failed") }
}

///|
async test "worktree-post-add finds a worktree the shell named by expansion" {
  let root = @fs.tmpdir(prefix="worktree-post-add-expand")
  defer @fs.rmdir(root, recursive=true)
  let main = root + "/main"
  @fs.mkdir(main + "/.docs", recursive=true)
  @fs.write_file(main + "/.gitignore", ".docs/\n")
  @fs.write_file(main + "/.docs/plan.md", "plan")
  git_in(main, ["init", "-q"])
  git_in(main, ["add", "."])
  git_in(main, ["commit", "-qm", "init"])
  git_in(main, ["worktree", "add", "-q", "../old", "-b", "old"])
  age_worktree(main, "old", "2 hours ago")
  let event = (command : String) => {
    let event : Json = {
      "tool_name": "Bash",
      "cwd": main,
      "tool_input": { "command": command },
      "tool_response": "Preparing worktree (new branch 'x')",
    }
    event
  }
  // Only an older worktree exists, so nothing is linked.
  assert_eq(worktree_post_add(event("git worktree add \"$X/new\"")), [])
  assert_eq(@fs.exists(root + "/old/.docs"), false)
  git_in(main, ["worktree", "add", "-q", "../new", "-b", "new"])
  git_in(main, ["worktree", "add", "-q", "../twin", "-b", "twin"])
  // Two worktrees made at the same moment leave the added one unknown.
  age_worktree(main, "new", "10 minutes ago")
  let (status, _, _) = @process.collect_output("touch", [
    "-r",
    main + "/.git/worktrees/new/commondir",
    main + "/.git/worktrees/twin/commondir",
  ])
  guard status == 0 else { fail("touch failed") }
  let command = "git worktree add \"$(pwd)/../new\" -b new"
  assert_eq(worktree_post_add(event(command)), [])
  // A checkout slower than a minute still counts, since Git wrote `commondir` before it.
  age_worktree(main, "twin", "2 hours ago")
  age_worktree(main, "new", "5 minutes ago")
  assert_eq(worktree_post_add(event(command)), [".docs"])
  assert_eq(@fs.kind(root + "/new/.docs", follow_symlink=false), SymLink)
  assert_eq(@fs.exists(root + "/old/.docs"), false)
  assert_eq(@fs.exists(root + "/twin/.docs"), false)
}
