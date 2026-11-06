// Any failure to read the repository lets the commit through, since this review only advises.

///|
pub async fn review(
  command : String,
  cwd : String,
  session~ : String,
  home~ : String,
) -> String? {
  guard find_commit(command, cwd) is Some(commit) else { return None }
  let diff = staged_diff(commit) catch { _ => return None }
  let files = added_comments(diff)
  guard files.iter().any(changes => !changes.comments.is_empty()) else {
    return None
  }
  let found = findings(files)
  let listing = render_comments(files, found)
  let state = state_path(commit.dir) catch { _ => return None }
  let previous = @fs.read_file(state).text() catch { _ => "" }
  // The same list as last time means the agent reviewed it and kept the comments.
  let outcome = if previous == listing { "passed" } else { "blocked" }
  if outcome == "blocked" {
    @fs.write_file(state, listing, create_mode=CreateOrTruncate) catch {
      _ => return None
    }
  }
  append_log(
    home,
    event_record(outcome, found, files, session~, dir=commit.dir),
  ) catch {
    _ => ()
  }
  if outcome == "passed" {
    None
  } else {
    Some(denial_reason(listing))
  }
}

///|
async fn staged_diff(commit : Commit) -> String {
  let options = ["--no-color", "--no-ext-diff", "--no-renames", "-U0"]
  if commit.includes_unstaged {
    // A repository without commits has no HEAD, so only the staged changes can be read.
    let (status, output) = git(commit.dir, ["diff", "HEAD", ..options])
    if status == 0 {
      return output
    }
  }
  let (status, output) = git(commit.dir, ["diff", "--cached", ..options])
  guard status == 0 else { fail("git diff failed") }
  output
}

///|
async fn state_path(dir : String) -> String {
  let (status, output) = git(dir, ["rev-parse", "--absolute-git-dir"])
  guard status == 0 else { fail("not a git repository") }
  @text.strip(output) + "/agent-hooks-comment-review"
}

///|
async fn git(dir : String, args : Array[String]) -> (Int32, String) {
  let (status, stdout, _) = @async.with_timeout(3000, () => {
    @process.collect_output(
      "git",
      ["-c", "core.quotepath=off", ..args],
      cwd=dir,
    )
  })
  (status, stdout.text())
}

///|
let max_listed : Int32 = 30

///|
fn render_comments(
  files : Array[FileChanges],
  found : Array[Finding],
) -> String {
  let lines = []
  let mut total = 0
  // Comments no rule caught are listed too, since whether one restates the code is the agent's call.
  for changes in files {
    for comment in changes.comments {
      total += 1
      guard lines.length() < max_listed else { continue }
      let labels = found
        .iter()
        .filter(finding => {
          finding.path == comment.path && finding.line == comment.line
        })
        .map(finding => finding.rule.label())
        .collect()
      let note = if labels.is_empty() { "" } else { "[\{labels.join("・")}] " }
      lines.push("- \{comment.path}:\{comment.line} \{note}\{comment.text}")
    }
  }
  if total > max_listed {
    lines.push("- ほか\{total - max_listed}件")
  }
  lines.join("\n")
}

///|
fn denial_reason(listing : String) -> String {
  guidance_lead + "\n\n" + listing + "\n\n" + guidance
}

///|
let guidance_lead : String =
  #|commit前に、追加したコメントを1件ずつ見直す。各コメントを消すか直すか残すかを決めてから、もう一度commitする。一覧が同じままのcommitは通す。[ ]はスクリプトが見つけた該当箇所。

///|
/// Every denial carries this text, so a single contrasting pair shows where a needless comment begins without lengthening it.
let guidance : String =
  #|判断の基準: 関数直上の役割は、名前だけで伝わらない場合に限り残す。それ以外のコメントは、名前や型から自然に考えつく別の書き方を退ける理由を1つ挙げられなければ消す。詳しくは指示文の「コメント規律」に従う。
  #|- 消す: `fn parse(...) -> Value` の上の `/// Returns the parsed value.`（名前と型で内容がすべて分かる）
  #|- 残す: `// A submodule's .git is a file, so is_dir would miss it`（`is_dir` を使う自然な案を退ける）

///|
fn event_record(
  outcome : String,
  found : Array[Finding],
  files : Array[FileChanges],
  session~ : String,
  dir~ : String,
) -> Json {
  let rules : Map[String, Json] = Map([])
  for finding in found {
    let id = finding.rule.id()
    let count = match rules.get(id) {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    rules[id] = Json::number(count + 1.0)
  }
  let comments = files
    .iter()
    .map(changes => changes.comments.length())
    .fold(init=0, (sum, count) => sum + count)
  {
    "time": Json::number(@env.now().to_double()),
    "session": Json::string(session),
    "dir": Json::string(dir),
    "outcome": Json::string(outcome),
    "rules": Json::object(rules),
    "comments": Json::number(comments.to_double()),
  }
}

///|
async fn append_log(home : String, record : Json) -> Unit {
  guard home != "" else { return }
  let dir = home + "/.local/state/claude"
  @fs.mkdir(dir, permission=0o700, recursive=true, allow_exist=true)
  // Repository paths can be private, so only the user may read the log.
  @fs.write_file(
    dir + "/comment-review-events.jsonl",
    record.stringify() + "\n",
    create_mode=OpenOrCreate,
    permission=0o600,
    append=true,
  )
}
