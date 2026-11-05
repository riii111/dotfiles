///|
/// Feeds `text` in chunks of `size` bytes and returns lines `start..=end`.
fn line_range(
  text : Bytes,
  start : Int32,
  end : Int32,
  size~ : Int32 = 3,
) -> String raise {
  let output = StringBuilder()
  let lines = LineRange::new(start, end, output)
  let mut offset = 0
  while offset < text.length() {
    let next = if offset + size < text.length() {
      offset + size
    } else {
      text.length()
    }
    if !lines.feed(text[offset:next]) {
      return output.to_string()
    }
    offset = next
  }
  lines.finish()
  output.to_string()
}

///|
test "line endings follow Python's text mode" {
  let text = b"a\r\nb\rc\n\r\nd"
  for size in [1, 2, 3, 64] {
    assert_eq(line_range(text, 1, 10, size~), "a\nb\nc\n\nd")
    assert_eq(line_range(text, 2, 3, size~), "b\nc\n")
    assert_eq(line_range(text, 5, 5, size~), "d")
    assert_eq(line_range(text, 6, 9, size~), "")
  }
  assert_eq(line_range(b"x\r", 1, 2), "x\n")
  assert_eq(line_range(b"\xe6\x97\xa5\xe6\x9c\xac\n", 1, 1, size=1), "日本\n")
  assert_eq(line_range(b"", 1, 1), "")
}

///|
test "reading stops at the last requested line" {
  assert_eq(line_range(b"ok\n\xff\n", 1, 1), "ok\n")
  let failed = try {
    ignore(line_range(b"ok\n\xff\n", 1, 2))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "line numbers are ASCII decimals and capped above the limit" {
  assert_eq(decimal("0012"), Some(12))
  assert_eq(decimal("00000000000000000001"), Some(1))
  assert_eq(decimal("99999999999999999999"), Some(max_line + 1))
  assert_eq(decimal(""), None)
  assert_eq(decimal("-1"), None)
  assert_eq(decimal("１"), None)
}

///|
async fn git(cwd : String, args : Array[String]) -> Unit {
  assert_eq(@process.run("git", ["-C", cwd, ..args]), 0)
}

///|
async fn write(path : String, text : String) -> Unit {
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
async test "only files under the skill folders and the trusted repository are readable" {
  let root = @fs.realpath(@fs.tmpdir(prefix="codex-read-lines-"))
  let home = root + "/home"
  let repository = home + "/ghq/github.com/riii111/test"
  let plugin = home + "/.codex/plugins/cache/openai-bundled/demo"
  let plugin_skill = plugin + "/1.0.0/skills"
  let outside = root + "/outside.txt"
  @fs.mkdir(repository, recursive=true)
  @fs.mkdir(plugin_skill, recursive=true)
  @fs.mkdir(home + "/.codex/skills", recursive=true)
  @fs.mkdir(home + "/.codex/skills-sibling", recursive=true)
  @fs.mkdir(home + "/ghq/github.com/riii111/test-sibling", recursive=true)
  git(repository, ["init", "-q"])
  git(repository, [
    "remote", "add", "origin", "https://github.com/riii111/test.git",
  ])
  write(repository + "/file.txt", "one\n")
  write(home + "/.codex/skills/SKILL.md", "skill\n")
  write(plugin_skill + "/SKILL.md", "plugin skill\n")
  write(plugin + "/SKILL.md", "plugin level\n")
  write(outside, "outside\n")
  write(home + "/.codex/outside.txt", "outside\n")
  write(home + "/.codex/skills-sibling/SKILL.md", "sibling\n")
  write(home + "/ghq/github.com/riii111/test-sibling/file.txt", "sibling\n")
  @fs.symlink(target=outside, repository + "/escape.txt")
  @fs.symlink(target=outside, plugin_skill + "/escape.txt")

  for
    path in [
      "file.txt",
      repository + "/file.txt",
      home + "/.codex/skills/SKILL.md",
      plugin_skill + "/SKILL.md",
    ] {
    assert_true(allowed_file(path, cwd=repository, home~) is Some(_))
  }
  for
    path in [
      plugin + "/SKILL.md",
      outside,
      "escape.txt",
      plugin_skill + "/escape.txt",
      home + "/.codex/skills-sibling/SKILL.md",
      home + "/ghq/github.com/riii111/test-sibling/file.txt",
      home + "/.codex/skills/../outside.txt",
      repository,
      "missing.txt",
    ] {
    assert_true(allowed_file(path, cwd=repository, home~) is None)
  }

  git(repository, [
    "remote", "set-url", "origin", "https://example.com/riii111/test.git",
  ])
  assert_true(allowed_file("file.txt", cwd=repository, home~) is None)
  assert_true(
    allowed_file(home + "/.codex/skills/SKILL.md", cwd=repository, home~)
    is Some(_),
  )
  @fs.rmdir(root, recursive=true)
}
