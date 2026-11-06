// The commit is stopped once per set of findings: the same findings again mean the agent reviewed them and kept the comments.
// Any failure to read the repository lets the commit through, since this review only advises.

///|
/// Returns the reason to stop the commit, or `None` to let it through.
pub async fn review(
  command : String,
  cwd : String,
  session~ : String,
  home~ : String,
) -> String? {
  guard find_commit(command, cwd) is Some(commit) else { return None }
  let diff = staged_diff(commit) catch { _ => return None }
  let files = added_comments(diff)
  let found = findings(files)
  guard !found.is_empty() else { return None }
  let listing = render_findings(found)
  let state = state_path(commit.dir) catch { _ => return None }
  let previous = @fs.read_file(state).text() catch { _ => "" }
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
fn render_findings(found : Array[Finding]) -> String {
  let lines = found
    .iter()
    .take(max_listed)
    .map(finding => {
      "- \{finding.path}:\{finding.line} [\{finding.rule.label()}] \{finding.text}"
    })
    .collect()
  if found.length() > max_listed {
    lines.push("- ほか\{found.length() - max_listed}件")
  }
  lines.join("\n")
}

///|
fn denial_reason(listing : String) -> String {
  "追加したコメントに、コメント規律に当たる可能性がある箇所がある。各箇所を直すか残すかを決めてから、もう一度commitする。指摘が同じままのcommitは通す。\n\n" +
  listing +
  "\n\n" +
  checklist
}

///|
let checklist : String =
  #|指摘以外の追加したコメントも、次の基準で見直す。
  #|- 関数の直上には、名前だけでは伝わらない役割を短く書く。理由や設計意図は書かない
  #|- 理由は該当する分岐・計算・設定のそばに、「理由のため、判断・処理をする」の順で書く
  #|- 挙動の説明や、名前・式の言い換えを書かない
  #|- 説明する対象の直前に書く
  #|- 呼び出し元や、そのモジュールの責務外の事情を書かない
  #|- 近くのコードに出てこない用語を使わない
  #|- 読み手に新しい疑問を残さない
  #|- 仕様の変更履歴はコミットメッセージやPRに書く
  #|- 公開APIのドキュメントコメントは、型や名前だけでは伝わらない契約があるときだけ書く
  #|- 1文は1行に書き、前置きや強調で膨らませない

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
