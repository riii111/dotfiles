///|
test "only a repository's own filter driver counts" {
  let entry = (scope : String, key : String) => {
    let entry : ConfigEntry = {
      scope,
      key,
      value: Some("git-lfs clean -- %f"),
    }
    entry
  }
  // Git LFS installs its filters globally.
  assert_false(repository_filter(entry("global", "filter.lfs.clean")))
  assert_false(repository_filter(entry("system", "filter.lfs.process")))
  assert_true(repository_filter(entry("local", "filter.lfs.smudge")))
  assert_true(repository_filter(entry("worktree", "filter.a.b.clean")))
  assert_false(repository_filter(entry("local", "filter.a.required")))
}

///|
test "a boolean fsmonitor value is not a hook" {
  for
    value in [None, Some(""), Some("TRUE"), Some("off"), Some("1"), Some("-1")] {
    assert_true(is_git_boolean(value))
  }
  for
    value in [
      Some("/usr/bin/hook"),
      Some(".git/hooks/fsmonitor-watchman"),
      Some("-"),
    ] {
    assert_false(is_git_boolean(value))
  }
}
