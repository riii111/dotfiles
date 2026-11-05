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
async test "a configured helper is denied unless the command turns it off" {
  let external = ["^diff\\.external$"]
  assert_eq(
    reason("git diff", configured=external),
    Some("Unsafe Git configuration is forbidden."),
  )
  assert_eq(reason("git diff --no-ext-diff", configured=external), None)
  assert_eq(
    reason("git fetch origin", configured=["^core\\.sshcommand$"]),
    Some("Unsafe Git configuration is forbidden."),
  )
}
