///|
fn chars(command : String) -> Array[Char] {
  command.iter().collect()
}

///|
test "a hard reset needs whitespace around reset and an option boundary after --hard" {
  for
    command in [
      "git reset --hard", "x && git -C a reset y --hard;ls", "git reset --hard\n",
      "/usr/bin/git reset --hard",
    ] {
    assert_true(mentions_hard_reset(chars(command)), msg=command)
  }
  for
    command in [
      "git reset --hard-ish", "git reset --hard_x", "git reset; --hard", "gitx reset --hard",
      "日本git reset --hard", "git reset\t", "git resetx --hard",
    ] {
    assert_false(mentions_hard_reset(chars(command)), msg=command)
  }
}

///|
test "a forced add counts only a final -f after a second whitespace" {
  for
    command in [
      "git  add x -f", "git add x -f", "git add x -f\n", "git add x -f '\"]",
    ] {
    assert_true(mentions_forced_add(chars(command)), msg=command)
  }
  for
    command in [
      "git add -f", "git add x -f y", "git add x -fx", "git add x; -f",
    ] {
    assert_false(mentions_forced_add(chars(command)), msg=command)
  }
}

///|
test "a recursive rm is a letter run with r after a dash, or --recursive" {
  for
    command in [
      "rm -rf x", "rm x -fR", "cd a && rm -fr y", "rm --recursive x", "/bin/rm -r x",
    ] {
    assert_true(mentions_recursive_rm(chars(command)), msg=command)
  }
  for command in ["rmdir -r", "rm -f x", "rm x; -r", "rm -1r", "arm -r"] {
    assert_false(mentions_recursive_rm(chars(command)), msg=command)
  }
}
