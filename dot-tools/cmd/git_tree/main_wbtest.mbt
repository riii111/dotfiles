///|
/// Runs Git in `cwd` without the user's configuration, with each call one second after the previous one.
async fn git(cwd : String, args : Array[String], clock : Ref[Int32]) -> Unit {
  clock.val += 1
  let date = "@\{clock.val} +0000"
  let status = @process.run("git", ["-C", cwd, ..args], extra_env={
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "test",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
    "GIT_AUTHOR_DATE": date,
    "GIT_COMMITTER_DATE": date,
  })
  assert_eq(status, 0)
}

///|
/// Creates `main -> a -> b`, `a -> c` and `main -> d` with `c` checked out and `d` in another worktree.
async fn hierarchy(root : String) -> String {
  let repository = root + "/repo"
  let clock = Ref(1_700_000_000)
  @fs.mkdir(repository)
  git(repository, ["init", "-q", "-b", "main"], clock)
  let commit = ["commit", "-q", "--allow-empty", "-m", "commit"]
  git(repository, commit, clock)
  git(repository, ["checkout", "-q", "-b", "a"], clock)
  git(repository, commit, clock)
  git(repository, ["checkout", "-q", "-b", "b"], clock)
  git(repository, commit, clock)
  git(repository, commit, clock)
  git(repository, ["checkout", "-q", "-b", "c", "a"], clock)
  git(repository, commit, clock)
  git(repository, ["checkout", "-q", "-b", "d", "main"], clock)
  git(repository, commit, clock)
  git(repository, ["checkout", "-q", "c"], clock)
  git(repository, ["worktree", "add", "-q", root + "/other", "d"], clock)
  repository
}

///|
async test "branches are nested under their fork point, colored only when current or in another worktree" {
  let root = @fs.realpath(@fs.tmpdir(prefix="git-tree-"))
  let repository = hierarchy(root)
  assert_eq(
    branch_tree(Git::new(Some(repository)), color=false),
    Some(
      (
        #|
        #|  main
        #|  ├── a (+1)
        #|  │   ├── c (+1) ★
        #|  │   └── b (+2)
        #|  └── d (+1) ● other
        #|
        #|
      ),
    ),
  )
  let current = "\u{1b}[1;32m"
  let worktree = "\u{1b}[36m"
  let reset = "\u{1b}[0m"
  assert_eq(
    branch_tree(Git::new(Some(repository)), color=true),
    Some(
      (
        $|
        $|  main
        $|  ├── a (+1)
        $|  │   ├── \{current}c (+1) ★\{reset}
        $|  │   └── b (+2)
        $|  └── \{worktree}d (+1) ● other\{reset}
        $|
        $|
      ),
    ),
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "a repository without main or master has no tree" {
  let root = @fs.realpath(@fs.tmpdir(prefix="git-tree-"))
  let clock = Ref(1_700_000_000)
  git(root, ["init", "-q", "-b", "dev"], clock)
  git(root, ["commit", "-q", "--allow-empty", "-m", "commit"], clock)
  assert_eq(branch_tree(Git::new(Some(root)), color=false), None)
  @fs.rmdir(root, recursive=true)
}
