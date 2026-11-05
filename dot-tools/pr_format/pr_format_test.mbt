///|
let good_body : String =
  #|close #12
  #|
  #|ログが長く失敗箇所を探しにくいため、成功テストの出力を省く
  #|
  #|- 失敗したテストだけを出力する
  #|- 既定の詳細度は変えない
  #|

///|
fn create_command(
  body : String,
  title~ : String = "ci: テストのログを減らす",
) -> String {
  "gh pr create --draft --title \"\{title}\" --body \"$(cat <<'EOF'\n\{body}EOF\n)\""
}

///|
async fn problems(
  event : Json,
  language~ : String? = Some("ja"),
) -> Array[String] {
  @pr_format.check(event, "/tmp", _ => language)
}

///|
async fn denies(command : String, language~ : String? = Some("ja")) -> Bool {
  !problems({ "tool_input": { "command": command } }, language~).is_empty()
}

///|
async fn denies_mcp(operation : String, input : Json) -> Bool {
  !problems({ "tool_name": "mcp__github__" + operation, "tool_input": input }).is_empty()
}

///|
async test "an issue is referenced with a closing keyword" {
  assert_true(
    denies(create_command(good_body.replace(old="close #12", new="Refs #12"))),
  )
  assert_false(
    denies(create_command(good_body.replace(old="close #12", new="Close #12"))),
  )
  assert_false(
    denies(create_command(good_body.replace(old="close #12", new=""))),
  )
}

///|
async test "a conforming pull request and other commands pass" {
  assert_false(denies(create_command(good_body)))
  assert_false(denies("git status"))
  assert_false(denies("gh pr edit 1 --add-label bug"))
}

///|
async test "a body the command does not contain is denied" {
  assert_true(
    denies("gh pr create --title \"ci: 軽くする\" --body-file body.md"),
  )
  assert_true(
    denies("gh pr create --title \"ci: 軽くする\" --body \"$BODY\""),
  )
}

///|
async test "a heredoc passed to --body-file is read" {
  let command = "gh pr create --title \"ci: 軽くする\" --body-file - <<'EOF'\n" +
    good_body +
    "- 補足（理由）\nEOF\n"
  assert_true(denies(command))
}

///|
async test "an edit is checked when it sets the title or body" {
  assert_true(denies("gh pr edit 1 --title \"軽くする\""))
}

///|
async test "the command is found inside a chain" {
  let command = "git push -u origin HEAD && " +
    create_command(good_body + "- 補足（理由）\n")
  assert_true(denies(command))
}

///|
async test "the configured language is required and followed" {
  for language in [None, Some("fr")] {
    assert_true(denies(create_command(good_body), language~))
  }
  assert_true(denies(create_command(good_body, title="ci: trim test logs")))
  assert_true(denies(create_command(good_body), language=Some("en")))
  let english = "close #12\n\nPassing tests flood the log and hide failures.\n"
  assert_false(
    denies(
      create_command(english, title="ci: trim test logs"),
      language=Some("en"),
    ),
  )
}

///|
async test "Japanese sentences end with a predicate and hold one clause" {
  for
    tail in [
      "省く。守る対象は保存期間とバケット名。", "省くので、集約すれば、確認は不要になる。",
    ] {
    assert_true(
      denies(create_command(good_body.replace(old="省く", new=tail))),
    )
  }
  assert_false(
    denies(
      create_command(
        good_body.replace(
          old="省く",
          new="省く。確認は不要になる。",
        ),
      ),
    ),
  )
  let english = "close #12\n\nThe log is noisy. Trimming it makes failures visible.\n"
  assert_false(
    denies(create_command(english, title="ci: trim logs"), language=Some("en")),
  )
}

///|
async test "a pull request through GitHub MCP is checked and must be a draft" {
  let good : Json = {
    "title": "ci: テストのログを減らす",
    "body": good_body,
    "draft": true,
  }
  assert_false(denies_mcp("create_pull_request", good))
  assert_true(
    denies_mcp("create_pull_request", {
      "title": "trim logs",
      "body": good_body,
      "draft": true,
    }),
  )
  assert_true(
    denies_mcp("create_pull_request", {
      "title": "ci: テストのログを減らす",
      "body": good_body + "- 3\n- 4\n",
      "draft": true,
    }),
  )
  assert_true(
    denies_mcp("create_pull_request", {
      "title": "ci: テストのログを減らす",
      "body": good_body,
    }),
  )
  assert_true(
    denies_mcp("create_pull_request", {
      "title": "ci: テストのログを減らす",
      "body": good_body,
      "draft": false,
    }),
  )
}

///|
async test "a GitHub MCP edit is checked only for what it changes" {
  assert_false(denies_mcp("update_pull_request", { "pullNumber": 3 }))
  assert_false(
    denies_mcp("update_pull_request", { "title": "fix: 失敗を出力する" }),
  )
  assert_true(denies_mcp("update_pull_request", { "title": "Update things" }))
  assert_false(
    denies_mcp("pull_request_read", { "title": "anything", "body": "x" }),
  )
}

///|
test "each rule names its problem" {
  let cases : Array[(String, String)] = [
    ("- 句点で終わる。", "箇条書きの文末に句点を付けない"),
    ("- [ ] 確認する", "確認チェックリストを書かない"),
    (
      "補足(理由)を書く", "カッコによる補足を使わない。補足は別の文にする",
    ),
    (
      "org/repo#12 を参照する", "IssueやPRの番号を文中に埋め込まない。Issueは先頭の `Close #N` の行に書き、PRの番号は書かない",
    ),
    (
      "https://github.com/o/r/pull/3 を見る", "IssueやPRの番号を文中に埋め込まない。Issueは先頭の `Close #N` の行に書き、PRの番号は書かない",
    ),
    (
      "日本語 English 混在", "本文の日本語と英語の間にスペースを入れない",
    ),
    (
      "Generated with [Claude Code](https://claude.ai/code)", "Claude Codeの署名とセッションのリンクを書かない。`Generated by Claude Code` の行と区切り線を消す",
    ),
  ]
  for case in cases {
    let (body, problem) = case
    assert_true(@pr_format.check_body(body).contains(problem))
  }
  for
    body in [
      "`code（x）` を使う", "[リンク](https://example.com/a_b) を貼る",
      "x#12", "issue#5", "```\nコード（中）\n```",
    ] {
    assert_eq(@pr_format.check_body(body), [])
  }
}

///|
test "titles follow Conventional Commits" {
  for
    title in [
      "feat(scope): 追加する", "fix!: 直す", "fix(x)!: 直す", "revert: 戻す",
    ] {
    assert_eq(@pr_format.check_title(title), [])
  }
  for
    title in [
      "trim logs", "feat(sc ope): x", "fix: ", "fixup: x", "feat(): 空", "feat:x",
      "fix:  空白",
    ] {
    assert_true(!@pr_format.check_title(title).is_empty())
  }
}

///|
test "references and bullets use Python's Unicode word and digit classes" {
  let reference = "IssueやPRの番号を文中に埋め込まない。Issueは先頭の `Close #N` の行に書き、PRの番号は書かない"
  for body in ["#12™ を見る", "#12\u{FE0F} を見る", "#١ を見る"] {
    assert_true(@pr_format.check_body(body).contains(reference))
  }
  assert_true(
    @pr_format.check_body("١. one\n٢. two\n٣. three\n٤. four").contains(
      "箇条書きが4個ある。3個以内に統合する",
    ),
  )
}

///|
/// Returns the folder whose `pr.language` the check reads for `event`, with the session in `/work/session`.
async fn language_folder(event : Json, home : String) -> String {
  let folder = Ref("")
  let _ = @pr_format.check(
    event,
    "/work/session",
    path => {
      folder.val = path
      Some("ja")
    },
    home~,
  )
  folder.val
}

///|
fn pr_event(prefix : String, args : String) -> Json {
  {
    "tool_input": {
      "command": prefix +
      "gh pr " +
      args +
      " --title \"ci: 軽くする\" --body \"$(cat <<'EOF'\n--repo other/repo\nEOF\n)\"",
    },
  }
}

///|
async test "the language is read from the pull request's repository" {
  let home = @fs.realpath(@fs.tmpdir(prefix="pr-format-"))
  let checkout = home + "/ghq/github.com/acme/app"
  @fs.mkdir(checkout, recursive=true)
  for
    args in [
      "create --repo acme/app", "create -R acme/app", "create --repo=acme/app", "create -Racme/app",
      "create --repo 'https://github.com/acme/app.git'", "edit 3 --repo github.com/acme/app",
      "edit https://github.com/acme/app/pull/3",
    ] {
    assert_eq(language_folder(pr_event("", args), home), checkout)
  }
  assert_eq(
    language_folder(
      pr_event("cd ~/ghq/github.com/acme/app && ", "create"),
      home,
    ),
    checkout,
  )
  assert_eq(
    language_folder(pr_event("cd /srv && cd app; ", "create"), home),
    "/srv/app",
  )
  assert_eq(
    language_folder(pr_event("cd /srv && ", "create --repo acme/app"), home),
    checkout,
  )
  assert_eq(
    language_folder(
      pr_event("cd /srv && ", "edit https://github.com/acme/app/pull/3"),
      home,
    ),
    checkout,
  )
  let command = (text : String) => {
    let event : Json = { "tool_input": { "command": text } }
    event
  }
  assert_eq(
    language_folder(
      command(
        "gh pr create --body \"$(cat <<'EOF'\nDescription\nEOF\n)\" --repo acme/app --title \"fix: 直す\"",
      ),
      home,
    ),
    checkout,
  )
  assert_eq(
    language_folder(
      command(
        "gh pr create --body 'Use --repo acme/other here' --repo acme/app --title 'fix: 直す'",
      ),
      home,
    ),
    checkout,
  )
  assert_eq(
    language_folder(
      command(
        "gh pr create --title 'fix: 直す' && gh repo view --repo acme/app",
      ),
      home,
    ),
    "/work/session",
  )
  assert_eq(
    language_folder(
      command(
        "gh pr create --body 'Explain <<EOF'\\\n --repo acme/app --title 'fix: 直す'",
      ),
      home,
    ),
    checkout,
  )
  assert_eq(
    language_folder(
      command(
        "gh pr create --title 'fix: 直す'\ngh repo view --repo acme/app",
      ),
      home,
    ),
    "/work/session",
  )
  for prefix in ["(cd /other && make); ", "cd /other | cat; ", "cd /other & "] {
    assert_eq(
      language_folder(pr_event(prefix, "create"), home),
      "/work/session",
    )
  }
  assert_eq(
    language_folder(
      pr_event("cd /srv && (cd /other && make) && ", "create"),
      home,
    ),
    "/srv",
  )
  for
    prefix in [
      "cd -- /srv/app && ", "cd -P /srv/app && ", "cd -LP -- /srv/app; ",
    ] {
    assert_eq(language_folder(pr_event(prefix, "create"), home), "/srv/app")
  }
  assert_eq(language_folder(pr_event("", "create"), home), "/work/session")
  assert_eq(
    language_folder(pr_event("", "create --repo acme/missing"), home),
    home,
  )
  assert_eq(
    language_folder(
      {
        "tool_name": "mcp__github__create_pull_request",
        "tool_input": {
          "owner": "acme",
          "repo": "app",
          "title": "ci: 軽くする",
        },
      },
      home,
    ),
    checkout,
  )
  @fs.rmdir(home, recursive=true)
}
