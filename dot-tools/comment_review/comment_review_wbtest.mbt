///|
test "find_commit reads the directory and whether unstaged changes go in" {
  let cases : Array[(String, String, Bool)] = [
    ("git commit -m \"feat: x\"", "/repo", false),
    ("cd sub && git commit -m x", "/repo/sub", false),
    ("git -C /other commit -m x", "/other", false),
    ("git add -A && git commit -m x", "/repo", true),
    ("git commit -am x", "/repo", true),
    ("git commit --all -m x", "/repo", true),
    ("git commit -m x file.txt", "/repo", true),
    ("git commit -m \"$(cat <<'EOF'\nfeat: x\nEOF\n)\"", "/repo", false),
  ]
  for case in cases {
    let (command, dir, includes_unstaged) = case
    guard find_commit(command, "/repo") is Some(commit) else {
      fail("no commit in \{command}")
    }
    assert_eq(commit.dir, dir)
    assert_eq(commit.includes_unstaged, includes_unstaged)
  }
}

///|
test "commands that record nothing are not commits" {
  for command in ["git status", "git commit --dry-run", "git commit -h"] {
    assert_true(find_commit(command, "/repo") is None)
  }
}

///|
let diff : String =
  #|diff --git a/src/a.mbt b/src/a.mbt
  #|--- a/src/a.mbt
  #|+++ b/src/a.mbt
  #|@@ -3,0 +4,6 @@ fn x
  #|+// Splits the input because
  #|+// the parser needs one line.
  #|+/// Returns the parsed value.
  #|+///|
  #|+let x = 1 // not a whole-line comment
  #|+  // TODO: fix
  #|diff --git a/README.md b/README.md
  #|--- a/README.md
  #|+++ b/README.md
  #|@@ -1,0 +1 @@
  #|+// not code
  #|diff --git a/pkg.generated.mbti b/pkg.generated.mbti
  #|--- a/pkg.generated.mbti
  #|+++ b/pkg.generated.mbti
  #|@@ -1,0 +1 @@
  #|+// Generated
  #|

///|
test "added_comments keeps whole-line comments of known languages" {
  let files = added_comments(diff)
  assert_eq(files.length(), 1)
  let file = files[0]
  assert_eq(file.path, "src/a.mbt")
  assert_eq(file.added, 6)
  let lines = file.comments.map(comment => (comment.line, comment.text))
  assert_eq(lines, [
    (4, "Splits the input because"),
    (5, "the parser needs one line."),
    (6, "Returns the parsed value."),
    (9, "TODO: fix"),
  ])
  assert_true(file.comments[2].kind is Doc)
}

///|
test "findings flag what a script can see" {
  let found = findings(added_comments(diff))
  let rules = found.map(finding => (finding.rule.id(), finding.line))
  assert_eq(rules, [("broken-sentence", 4), ("bare-todo", 9)])
}

///|
fn comments(texts : Array[String]) -> Array[FileChanges] {
  [
    {
      path: "a.py",
      added: 100,
      comments: texts.mapi((index, text) => {
        path: "a.py",
        line: index + 1,
        kind: Normal,
        text,
      }),
    },
  ]
}

///|
fn rule_ids(texts : Array[String]) -> Array[String] {
  findings(comments(texts)).map(finding => finding.rule.id())
}

///|
test "each rule" {
  assert_eq(rule_ids(["a.", "b.", "c.", "d."]), ["long-block"])
  assert_eq(rule_ids(["Reads the file (the cached one)."]), ["parenthetical"])
  assert_eq(
    rule_ids(["キャッシュを読む（古い場合は捨てる）。"]),
    ["parenthetical"],
  )
  assert_eq(rule_ids(["Calls run() first."]), [])
  assert_eq(rule_ids(["Mirrors `^(?:[-*+]) (x)`."]), [])
  assert_eq(rule_ids(["----------"]), ["divider"])
  assert_eq(rule_ids(["=== Setup ==="]), ["divider"])
  assert_eq(rule_ids(["以前はキャッシュを共有していた。"]), [
    "change-history",
  ])
  assert_eq(rule_ids(["ユーザーが追加した設定を優先する。"]), [])
  assert_eq(rule_ids(["新たに接続を張らず既存を使う。"]), [])
  assert_eq(rule_ids(["The cache is no longer shared."]), ["change-history"])
  assert_eq(rule_ids(["念のため再試行する。"]), ["filler"])
  assert_eq(rule_ids(["Note that the order matters."]), ["filler"])
  assert_eq(rule_ids(["TODO"]), ["bare-todo"])
  assert_eq(
    rule_ids(["TODO: 上流がv2を出したら、この分岐を消す"]),
    [],
  )
}

///|
test "the same sentence twice is a duplicate" {
  let files = comments(["Cancels the payment on delete."])
  files.push({
    path: "b.py",
    added: 100,
    comments: [
      {
        path: "b.py",
        line: 7,
        kind: Normal,
        text: "Cancels the payment on delete.",
      },
    ],
  })
  let found = findings(files).map(finding => (finding.rule.id(), finding.path))
  assert_eq(found, [("duplicate", "a.py"), ("duplicate", "b.py")])
}

///|
test "a file that is mostly comments is dense" {
  let texts = ["One.", "", "Two.", "", "Three.", "", "Four.", "", "Five."]
  let file : FileChanges = {
    path: "a.py",
    added: 12,
    comments: texts
    .mapi((index, text) => Comment::{
      path: "a.py",
      line: index * 2,
      kind: Normal,
      text,
    })
    .filter(comment => comment.text != ""),
  }
  let found = findings([file]).map(finding => finding.rule.id())
  assert_eq(found, ["dense"])
}

///|
test "the reason lists every added comment and marks the findings" {
  let files = comments(["Reads the config.", "TODO"])
  let listing = render_comments(files, findings(files))
  assert_eq(
    listing, "- a.py:1 Reads the config.\n- a.py:2 [着手条件のないTODO] TODO",
  )
  let reason = denial_reason(listing)
  assert_true(reason.contains(listing))
  assert_true(reason.contains("コメント規律"))
}

///|
let jsdoc : String =
  #|diff --git a/a.ts b/a.ts
  #|--- a/a.ts
  #|+++ b/a.ts
  #|@@ -1,0 +1,6 @@
  #|+/**
  #|+ * Parses the header
  #|+ * @param raw the line
  #|+ * @returns the value
  #|+ * and its offset.
  #|+ */
  #|

///|
test "a multi-line JSDoc stays a doc comment" {
  let files = added_comments(jsdoc)
  assert_true(files[0].comments.iter().all(comment => comment.kind is Doc))
  assert_eq(findings(files).map(finding => finding.rule.id()), [
    "broken-sentence", "broken-sentence", "broken-sentence",
  ])
}
