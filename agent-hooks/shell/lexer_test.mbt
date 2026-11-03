// Expected words were captured from Python's shlex, which the hooks replaced.

///|
test "split_words splits words and quoted strings" {
  assert_eq(
    @shell.split_words(
      "git push --force origin main",
      punctuation=";&|()",
      comments=true,
    ),
    ["git", "push", "--force", "origin", "main"],
  )
  assert_eq(
    @shell.split_words(
      "echo 'a b' \"c\\\"d\" e\\ f",
      punctuation=";&|()",
      comments=true,
    ),
    ["echo", "a b", "c\"d", "e f"],
  )
  assert_eq(
    @shell.split_words("echo '' \"\"", punctuation="();<>|&", comments=false),
    ["echo", "", ""],
  )
  assert_eq(
    @shell.split_words(
      "echo \"a\\nb\" \"a\\\\b\"",
      punctuation="();<>|&",
      comments=false,
    ),
    ["echo", "a\\nb", "a\\b"],
  )
}

///|
test "split_words keeps runs of punctuation together" {
  assert_eq(
    @shell.split_words("a&&b||c;d|&e", punctuation=";&|()", comments=true),
    ["a", "&&", "b", "||", "c", ";", "d", "|&", "e"],
  )
  assert_eq(
    @shell.split_words(
      "gh pr comment 1 >out 2>&1",
      punctuation="();<>|&",
      comments=false,
    ),
    ["gh", "pr", "comment", "1", ">", "out", "2", ">&", "1"],
  )
}

///|
test "split_words drops the rest of the line after a comment" {
  assert_eq(
    @shell.split_words("git push # --force", punctuation=";&|()", comments=true),
    ["git", "push"],
  )
  assert_eq(@shell.split_words("x#y z", punctuation=";&|()", comments=true), [
    "x",
  ])
  assert_eq(
    @shell.split_words("echo a#b", punctuation="();<>|&", comments=false),
    ["echo", "a#b"],
  )
}

///|
test "split_words rejects unbalanced quoting" {
  assert_true(syntax_error("echo 'open") is Some(UnclosedQuote))
  assert_true(syntax_error("echo a\\") is Some(DanglingEscape))
}

///|
fn syntax_error(command : String) -> @shell.ShellSyntaxError? {
  try @shell.split_words(command, punctuation=";&|()", comments=true) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
}

///|
test "split_on_whitespace splits on any whitespace" {
  assert_eq(@shell.split_on_whitespace(" a\tb\u{3000}c \n"), ["a", "b", "c"])
}
