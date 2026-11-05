// Denies `gh pr create` and `gh pr edit` when the title or body breaks the mechanical format rules.
// A pull request the GitHub MCP server creates or edits, as in Claude Code cloud sessions, is checked the same way from
// its structured title and body, and must be created as a draft.
// The language comes from `git config pr.language` (ja or en). The user sets it per repository, so an unset value blocks
// the pull request instead of being guessed.

///|
pub let denial_header : String = "PRのタイトルか本文を次のとおり直し、同じコマンドを再実行してください。"

///|
let unset_language : String = "このリポジトリのPRの言語が未設定か不正。ユーザーに英語か日本語かを確認し、`git config pr.language en` か `git config pr.language ja` を設定する"

///|
let unreadable_body : String = "本文をコマンド内に直接書く。`--body \"$(cat <<'EOF' ... EOF)\"` の形にする。ファイルや変数を経由すると本文を検査できない"

///|
/// Returns the problems of the pull request a PreToolUse event creates or edits.
/// `read_language` returns `git config pr.language` for a folder; an error it raises is passed on.
pub async fn check(
  event : Json,
  cwd : String,
  read_language : async (String) -> String?,
) -> Array[String] {
  let name = match event {
    { "tool_name": String(name), .. } => name
    _ => ""
  }
  let input = match event {
    { "tool_input": Object(input), .. } => Json::object(input)
    _ => Json::object({})
  }
  let operation = @github_tool.operation(name)
  if operation
    is Some("create_pull_request" | "update_pull_request" as operation) {
    let title = text_field(input, "title")
    let body = text_field(input, "body")
    let problems = []
    if operation == "create_pull_request" && !(input is { "draft": True, .. }) {
      problems.push("PRはDraftで作る。`draft: true` を指定する")
    }
    if title is Some(title) {
      problems.push_iter(check_title(title).iter())
    }
    if body is Some(body) {
      problems.push_iter(check_body(body).iter())
    }
    if title is Some(_) || body is Some(_) {
      problems.push_iter(
        language_problems(cwd, title, body, read_language).iter(),
      )
    }
    return problems
  }

  guard text_field(input, "command") is Some(command) &&
    read_command(command) is Some(pr) else {
    return []
  }
  let problems = []
  if pr.title is Some(title) {
    problems.push_iter(check_title(title).iter())
  }
  if pr.body is Some(body) {
    problems.push_iter(check_body(body).iter())
  } else if pr.unreadable_body {
    problems.push(unreadable_body)
  }
  if pr.title is Some(_) || pr.body is Some(_) {
    problems.push_iter(
      language_problems(cwd, pr.title, pr.body, read_language).iter(),
    )
  }
  problems
}

///|
fn text_field(input : Json, key : String) -> String? {
  match input {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
async fn language_problems(
  cwd : String,
  title : String?,
  body : String?,
  read_language : async (String) -> String?,
) -> Array[String] {
  match read_language(cwd) {
    Some("ja" | "en" as language) => check_language(language, title, body)
    _ => [unset_language]
  }
}

///|
/// The reason shown when the pull request is denied.
pub fn denial_reason(problems : Array[String]) -> String {
  let reason = StringBuilder()
  reason.write_string(denial_header)
  for problem in problems {
    reason.write_string("\n- \{problem}")
  }
  reason.to_string()
}

///|
/// Reads `git config pr.language` in `cwd`; an unset value gives `None`, and Git that cannot run or answer in three seconds raises.
pub async fn read_language(cwd : String) -> String? {
  let (_, stdout, _) = @async.with_timeout(3000, () => {
    @process.collect_output("git", ["-C", cwd, "config", "--get", "pr.language"])
  })
  let language = @text.strip(stdout.text())
  if language == "" {
    None
  } else {
    Some(language)
  }
}
