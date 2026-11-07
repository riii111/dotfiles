///|
async fn reason(command : String, configured~ : Array[String] = []) -> String? {
  @permission.denial_reason(command, fn(pattern) {
    configured.contains(pattern)
  })
}

///|
test "shell syntax outside single quotes is found" {
  for
    command in [
      "git status\ntouch x", "git status `id`", "git status > x", "a; b", "a && b",
      "echo \"$(id)\"", "echo $(id)", "(git status)",
    ] {
    assert_true(@permission.has_shell_syntax(command), msg=command)
  }
  for
    command in [
      "git log --format='a>b'", "echo '$(id)'", "echo \"a\\\"b\"", "echo \\;", "git status",
    ] {
    assert_false(@permission.has_shell_syntax(command), msg=command)
  }
}

///|
test "a direct command skips leading assignments" {
  assert_eq(
    @permission.direct_command("A=1 B= git status"),
    Some(("git", ["status"])),
  )
  assert_eq(@permission.direct_command("A=1"), None)
  assert_eq(@permission.direct_command("git 'open"), None)
  assert_eq(@permission.direct_command("=x git"), Some(("=x", ["git"])))
}

///|
async test "destructive commands are denied, abbreviated options included" {
  let cases = [
    ("git reset --har HEAD", "Hard reset is forbidden."),
    ("git switch --force-c old", "Forced branch switching is forbidden."),
    ("git switch --or empty", "Orphan branch switching is forbidden."),
    ("git gc --prune now", "Immediate Git object pruning is forbidden."),
    ("git gc --prune=now", "Immediate Git object pruning is forbidden."),
    ("git push origin :old", "Destructive push is forbidden."),
    ("git restore -W .", "Restoring the entire working tree is forbidden."),
    ("git -c core.pager=cat log", "Git config overrides are forbidden."),
    ("git -cdiff.external=x diff", "External Git diff helpers are forbidden."),
    ("GIT_PAGER=less git log", "Git environment overrides are forbidden."),
    (
      "gh auth status --hostname h -t", "GitHub access-token output is forbidden.",
    ),
    ("terraform -chdir=infra apply", "Terraform state mutation is forbidden."),
    ("/bin/rm -Rf build", "Recursive file deletion is forbidden."),
    ("nice /usr/bin/git reset --hard", "Hard reset is forbidden."),
    ("git status && git add x -f", "Force-add is forbidden."),
    ("ls | rm -r x", "Recursive file deletion is forbidden."),
    ("x GIT_EXTERNAL_DIFF=y", "External Git diff helpers are forbidden."),
  ]
  for case in cases {
    let (command, expected) = case
    assert_eq(reason(command), Some(expected), msg=command)
  }
}

///|
async test "ordinary commands pass" {
  for
    command in [
      "git gc --prune=a=now", "git restore --staged .", "git add -- --force", "git stash pop",
      "terraform state list", "rm file", "rmdir build", "gh search code \"auth token\"",
      "git reset --hard-ish", "echo 'unclosed",
    ] {
    assert_eq(reason(command), None, msg=command)
  }
}

///|
/// Commands decided by their text alone, for both Codex events; the hook's shell test keeps the Git-state cases.
async test "the command table" {
  let denied = [
    "git reset HEAD~1 --hard", "FOO=1 git reset --hard", "git restore .", "git restore :/",
    "git restore --staged --worktree .", "git switch -f old", "git switch -C old",
    "git switch --force-create old", "git switch --discard-changes old", "git branch -D old",
    "git branch --delete --force old", "git branch --delete -f old", "git fetch -f origin",
    "git fetch --force origin", "git fetch origin +main:main", "git fetch --update-head-ok origin",
    "git rebase --exec \"touch outside\" main", "git switch --orphan empty", "git diff --output=/tmp/codex-leak main",
    "git diff --no-index /etc/hosts /etc/passwd", "GIT_SEQUENCE_EDITOR=\"touch outside\" git rebase -i main",
    "GIT_SSH_COMMAND=\"touch outside\" git fetch origin", "GIT_EDITOR=\"touch outside\" git commit",
    "git add --for ignored", "git switch --disc old", "git switch --force-c old",
    "git switch --or empty", "git rebase --ex \"touch outside\" main", "git reset --har HEAD",
    "git push --mir origin", "git push --del origin old", "git push --pru origin",
    "git clean --for -d", "git checkout -- .", "git stash clear", "git stash drop",
    "git add -f ignored", "git clean -fdx", "git gc --prune=now", "git -c alias.x='!git push --force origin HEAD' x",
    "git -c core.sshCommand='touch /tmp/outside' fetch origin", "git --config-env=alias.x=GIT_ALIAS x",
    "git -c core.pager=cat log", "git -C repo push origin +main:main", "git push origin :old",
    "git push -d origin old", "git push --prune origin", "gh auth token", "gh auth status --show-token",
    "gh auth status --hostname github.com --show-token", "gh auth status --hostname github.com -t",
    "gh repo delete owner/repo", "gh ssh-key add key.pub", "gh gpg-key add key.asc",
    "gh auth login", "gh auth refresh", "gh auth setup-git", "gcloud auth print-access-token",
    "gcloud projects delete project", "gcloud storage rm gs://bucket/object", "gcloud run jobs delete job",
    "gcloud run services delete service", "gcloud iam service-accounts keys create key.json",
    "terraform apply", "terraform state rm resource.name", "terraform state mv old new",
    "terraform taint resource.name", "terraform import resource.name id", "terraform force-unlock lock-id",
    "terraform workspace delete old", "chezmoi purge", "chezmoi destroy", "bq rm dataset",
    "sudo command", "chmod 777 file", "find . -delete", "/usr/bin/git reset --hard",
    "/bin/rm -rf build", "rm a --recursive",
    // Indirection and compound shell syntax.
     "eval 'git reset --hard'", "exec /usr/bin/git reset --hard", "printf build | xargs rm -rf",
    "find . -exec rm -rf '{}' +", "nice -n 5 /usr/bin/git reset --hard", "command -p git reset --hard",
    "env -S 'git reset --hard'", "if true; then git reset --hard; fi", "printf 'git reset --hard\\n' | sh",
    "git -c alias.x='!git reset --hard' x", "nohup git reset --hard", "PATH=/tmp:$PATH git status",
    "GIT_PAGER='touch /tmp/outside' git log", "PAGER='touch /tmp/outside' git log",
  ]
  for command in denied {
    assert_true(reason(command) is Some(_), msg=command)
  }
  // Ordinary development work and prompt-class operations, which the sandbox still governs.
  let passed = [
    "git add -- --force", "rm file", "rm agent-desk/started_at", "echo \"$HOME\"",
    "git diff \"$(git merge-base main HEAD)\"", "rg foo src/*.rs", "source .venv/bin/activate",
    "git diff --no-ext-diff --no-textconv", "rg textconv src", "git restore --staged .",
    "gh search code \"auth token\"", "git stash pop", "terraform state list", "GIT_PAGER=cat git status",
  ]
  for command in passed {
    assert_eq(reason(command), None, msg=command)
  }
}

///|
async test "approvals that need no repository" {
  let environment = { "HOME": "/home/u" }
  let lock = "/home/u/agent-desk/.lock"
  let decide = async fn(command) {
    match @permission.decide("PermissionRequest", command, "/", environment) {
      Some(Allow) => "allow"
      Some(Deny(_)) => "deny"
      None => "none"
    }
  }
  let cases = [
    ("gh auth status", "allow"),
    ("gh auth status --hostname github.com", "none"),
    ("gh auth\nstatus", "none"),
    ("gh\nauth status", "none"),
    ("rm \{lock}/started_at", "allow"),
    ("rmdir \{lock}", "allow"),
    ("rmdir /home/u/agent-desk", "none"),
    ("rm \{lock}/started_at /home/u/other", "none"),
    ("rm -rf \{lock}", "deny"),
  ]
  for case in cases {
    let (command, expected) = case
    assert_eq(decide(command), expected, msg=command)
  }
}

///|
async test "a configured helper is denied unless the command turns it off" {
  let external = ["^diff\\.external$"]
  assert_eq(
    reason("git diff", configured=external),
    Some("Unsafe Git configuration is forbidden."),
  )
  assert_eq(reason("git diff --no-ext-diff", configured=external), None)
  let driver = ["^diff\\..*\\.command$"]
  assert_true(reason("git diff", configured=driver) is Some(_))
  assert_eq(reason("git diff --no-ext-diff", configured=driver), None)
  let textconv = ["^diff\\..*\\.textconv$"]
  assert_true(reason("git show", configured=textconv) is Some(_))
  assert_eq(reason("git show --no-textconv", configured=textconv), None)
  assert_eq(
    reason("git fetch origin", configured=["^core\\.sshcommand$"]),
    Some("Unsafe Git configuration is forbidden."),
  )
}

///|
async test "one configuration lookup finds each helper" {
  let repo = @fs.tmpdir(prefix="permission-config")
  defer @fs.rmdir(repo, recursive=true)
  let git = async fn(args : Array[String]) {
    guard @git_trust.run_git(repo, args).status == 0 else { fail("git failed") }
  }
  git(["init", "-q"])
  let decide = async fn(command) {
    @permission.decide("PreToolUse", command, repo, {})
  }
  assert_true(decide("git diff") is None)
  let cases = [
    ("diff.external", "x", "git diff"),
    ("diff.a.textconv", "x", "git log -p"),
    ("diff.a.b.textconv", "x", "git show"),
    ("diff.a.command", "x", "git diff"),
    ("core.sshCommand", "x", "git fetch origin"),
    ("core.gitProxy", "x", "git ls-remote origin"),
  ]
  for case in cases {
    let (key, value, command) = case
    git(["config", key, value])
    assert_true(decide(command) is Some(Deny(_)), msg=key)
    git(["config", "--unset", key])
  }
  // A key that only contains a pattern's name is not that helper.
  git(["config", "diff.externalx", "x"])
  assert_true(decide("git diff") is None)
}
