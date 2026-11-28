// Denies `gh pr create` and `gh pr edit` when the title or body breaks the mechanical format rules.
// A pull request the GitHub MCP server creates or edits, as in Claude Code cloud sessions, is checked the same way from
// its structured title and body, and must be created as a draft.
// The language, ja or en, comes from the Git configuration of the pull request's repository, not of the session's folder.
// `pr.<owner>/<repo>.language` and `pr.<owner>.language` win over `pr.language`, so a repository without a checkout still has its own language.
// An unset value blocks the pull request instead of being guessed.

///|
pub let denial_header : String = "PRのタイトルか本文を次のとおり直し、同じコマンドを再実行してください。"

///|
let unset_language : String = "このリポジトリのPRの言語が未設定か不正。ユーザーに英語か日本語かを確認し、`git config pr.language en` か `ja` を設定する。チェックアウトのないリポジトリは `git config --global pr.<owner>.language` か `pr.<owner>/<repo>.language` で設定する"

///|
let unreadable_body : String = "本文をコマンド内に直接書く。`--body \"$(cat <<'EOF' ... EOF)\"` の形にする。ファイルや変数を経由すると本文を検査できない"

///|
/// Returns the problems of the pull request a PreToolUse event creates or edits.
/// `read_config` returns `git config <key>` for a folder and key; an error it raises is passed on.
/// `home` defaults to `$HOME`.
pub async fn check(
  event : Json,
  cwd : String,
  read_config : async (String, String) -> String?,
  home? : String,
) -> Array[String] {
  let home = match home {
    Some(home) => home
    None => @env.get_env_var("HOME").unwrap_or("")
  }
  let repository = target(event, cwd, home)
  // One budget covers every key, so the lookup stays within the three seconds the hook timeout allows for it.
  let language = () => {
    @async.with_timeout(3000, () => {
      configured_language(repository, home, read_config)
    })
  }
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
    problems.push_iter(format_problems(title, body).iter())
    problems.push_iter(language_problems(language, title, body).iter())
    return problems
  }

  guard text_field(input, "command") is Some(command) &&
    read_command(command) is Some(pr) else {
    return []
  }
  let problems = format_problems(pr.title, pr.body)
  if pr.unreadable_body {
    problems.push(unreadable_body)
  }
  problems.push_iter(language_problems(language, pr.title, pr.body).iter())
  problems
}

///|
fn format_problems(title : String?, body : String?) -> Array[String] {
  let problems = []
  if title is Some(title) {
    problems.push_iter(check_title(title).iter())
  }
  if body is Some(body) {
    problems.push_iter(check_body(body).iter())
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
async fn configured_language(
  repository : Target,
  home : String,
  read_config : async (String, String) -> String?,
) -> String? {
  let folder = language_folder(repository, home)
  for key in language_keys(repository) {
    if read_config(folder, key) is Some(value) {
      return Some(value)
    }
  }
  None
}

///|
async fn language_problems(
  language : async () -> String?,
  title : String?,
  body : String?,
) -> Array[String] {
  guard title is Some(_) || body is Some(_) else { return [] }
  match language() {
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
/// Reads `git config <key>` in `cwd`; an unset value gives `None`, and Git that cannot run raises.
pub async fn read_config(cwd : String, key : String) -> String? {
  let (_, stdout, _) = @process.collect_output("git", [
    "-C", cwd, "config", "--get", key,
  ])
  let value = @text.strip(stdout.text())
  if value == "" {
    None
  } else {
    Some(value)
  }
}
