///|
let head : String = "1111111111111111111111111111111111111111"

///|
let moved : String = "2222222222222222222222222222222222222222"

///|
priv struct Stored {
  id : String
  path : String
  line : Int32
  body : String
  mut state : String
}

///|
priv struct Fake {
  viewer : String
  mut head : String
  mut review : String?
  mut review_commit : String
  stored : Array[Stored]
  log : Array[String]
  mut writes : Int32
  mut lost_response_write : Int32
  mut lost_response_applied : Bool
  mut reads_broken : Bool
  mut on_files : () -> Unit
  mut before_write : () -> Unit
  mut accepts_submitted_writes : Bool
  mut listed_state : String
}

///|
fn Fake::new() -> Fake {
  {
    viewer: "alice",
    head,
    review: None,
    review_commit: head,
    stored: [],
    log: [],
    writes: 0,
    lost_response_write: 0,
    lost_response_applied: false,
    reads_broken: false,
    on_files: () => (),
    before_write: () => (),
    accepts_submitted_writes: false,
    listed_state: "PENDING",
  }
}

///|
fn operation_name(operation : Operation) -> String {
  match operation {
    Viewer => "Viewer"
    Snapshot(_) => "Snapshot"
    PullFiles(_, _) => "PullFiles"
    StartReview(_, _) => "StartReview"
    AddThread(_, _, _) => "AddThread"
  }
}

///|
let files_json : Json = [
  {
    "filename": "src/a.txt",
    "patch": "@@ -10,3 +10,4 @@ fn\n a\n+b\n c\n d\n@@ -40,2 +41,1 @@\n-x\n y",
  },
  { "filename": "gone.txt", "patch": "@@ -1,2 +0,0 @@\n-p\n-q" },
  { "filename": "image.bin" },
]

///|
fn Fake::snapshot(self : Fake) -> Json {
  let comments : Array[Json] = self.stored.map(stored => {
    "id": stored.id,
    "path": stored.path,
    "line": stored.line,
    "originalLine": stored.line,
    "state": stored.state,
    "subjectType": "LINE",
    "body": stored.body,
  })
  let nodes : Array[Json] = match self.review {
    None => []
    Some(id) =>
      [
        {
          "id": id,
          "state": self.listed_state,
          "url": "https://github.com/o/r/pull/7#pullrequestreview-9",
          "author": { "login": self.viewer },
          "commit": { "oid": self.review_commit },
          "comments": {
            "pageInfo": { "hasNextPage": false },
            "nodes": comments,
          },
        },
        {
          "id": "someone-else",
          "state": "PENDING",
          "url": "https://github.com/o/r/pull/7#pullrequestreview-1",
          "author": { "login": "mallory" },
          "commit": { "oid": self.review_commit },
          "comments": { "pageInfo": { "hasNextPage": false }, "nodes": [] },
        },
      ]
  }
  {
    "data": {
      "repository": {
        "pullRequest": {
          "id": "PR_7",
          "state": "OPEN",
          "headRefOid": self.head,
          "url": "https://github.com/o/r/pull/7",
          "reviews": { "pageInfo": { "hasNextPage": false }, "nodes": nodes },
        },
      },
    },
  }
}

///|
fn Fake::send(self : Fake, operation : Operation) -> Json raise Failure {
  let name = operation_name(operation)
  self.log.push(name)
  match operation {
    Viewer => return { "data": { "viewer": { "login": self.viewer } } }
    Snapshot(_) => {
      if self.reads_broken {
        raise Api("connection reset")
      }
      return self.snapshot()
    }
    PullFiles(_, page) => {
      (self.on_files)()
      return if page == 1 { files_json } else { [] }
    }
    _ => ()
  }
  self.writes += 1
  (self.before_write)()
  let lost = self.writes == self.lost_response_write
  if lost && !self.lost_response_applied {
    raise Api("connection reset")
  }
  let response = self.apply(operation)
  if lost {
    raise Api("connection reset")
  }
  response
}

///|
fn Fake::apply(self : Fake, operation : Operation) -> Json raise Failure {
  match operation {
    StartReview(_, commit) => {
      if self.review is Some(_) {
        raise Api("User can only have one pending review per pull request")
      }
      self.review = Some("PRR_1")
      self.review_commit = commit
      {
        "data": {
          "addPullRequestReview": {
            "pullRequestReview": { "id": "PRR_1", "state": "PENDING" },
          },
        },
      }
    }
    AddThread(review_id, draft, body) => {
      if self.review != Some(review_id) && !self.accepts_submitted_writes {
        raise Api("Could not resolve to a pending review")
      }
      let state = if self.review == Some(review_id) {
        "PENDING"
      } else {
        "SUBMITTED"
      }
      let id = "PRRC_\{self.stored.length() + 1}"
      self.stored.push({ id, path: draft.path, line: draft.line, body, state, })
      {
        "data": {
          "addPullRequestReviewThread": {
            "thread": {
              "comments": { "nodes": [{ "id": id, "state": state }] },
            },
          },
        },
      }
    }
    _ => raise Api("not a write")
  }
}

///|
fn Fake::submit(self : Fake) -> Unit {
  for stored in self.stored {
    stored.state = "SUBMITTED"
  }
  self.review = None
}

///|
fn Fake::add_manual(
  self : Fake,
  path : String,
  line : Int32,
  body : String,
) -> Unit {
  self.review = Some("PRR_1")
  self.stored.push({
    id: "PRRC_\{self.stored.length() + 1}",
    path,
    line,
    body,
    state: "PENDING",
  })
}

///|
async fn call(
  fake : Fake,
  command : String,
  input : Json?,
  sha~ : String = head,
  owner~ : String = "chat-1",
) -> Report {
  let args = [command, "--repo", "o/r", "--pr", "7", "--owner", owner]
  if command != "status" {
    args.push("--sha")
    args.push(sha)
  }
  run(args, None, () => input.map(json => json.stringify()).unwrap_or(""), operation => {
    fake.send(operation)
  })
}

///|
fn drafts(items : Array[(String, Int32, String)]) -> Json {
  let comments : Array[Json] = items.map(item => {
    "path": item.0,
    "line": item.1,
    "body": item.2,
  })
  { "comments": comments }
}

///|
fn write_count(fake : Fake) -> Int32 {
  fake.log.filter(name => name is ("StartReview" | "AddThread")).length()
}

///|
async test "saves comments into a new pending review at the confirmed commit" {
  let fake = Fake::new()
  let report = call(
    fake,
    "add",
    Some(
      drafts([("src/a.txt", 11, "first\nsecond"), ("src/a.txt", 41, "again")]),
    ),
  )
  assert_eq(report.code, 0)
  assert_true(report.text.contains("saved 2 new comments, 0 already saved"))
  assert_true(
    report.text.contains(
      "pending review: PENDING https://github.com/o/r/pull/7#pullrequestreview-9",
    ),
  )
  assert_true(report.text.contains("2 in total, 2 saved by this owner"))
  assert_eq(fake.review_commit, head)
  assert_eq(fake.stored.length(), 2)
  assert_eq(
    fake.stored[0].body,
    "first\nsecond\n\n<!-- pending-review owner=chat-1 side=RIGHT -->",
  )
  assert_true(fake.stored.iter().all(stored => stored.state == "PENDING"))
  assert_eq(fake.log, [
    "Viewer", "Snapshot", "PullFiles", "Snapshot", "StartReview", "AddThread", "AddThread",
    "Snapshot",
  ])
}

///|
async test "adds to an existing pending review and leaves its manual comments alone" {
  let fake = Fake::new()
  fake.add_manual("src/a.txt", 11, "my own note")
  let report = call(
    fake,
    "add",
    Some(drafts([("src/a.txt", 12, "from the chat")])),
  )
  assert_eq(report.code, 0)
  assert_eq(fake.stored[0].body, "my own note")
  assert_eq(fake.stored.length(), 2)
  assert_false(fake.log.contains("StartReview"))
  assert_true(report.text.contains("[manual]"))
}

///|
async test "the update subcommand is gone and saved comments are never rewritten" {
  let fake = Fake::new()
  fake.add_manual("src/a.txt", 11, "my own note")
  assert_eq(
    call(fake, "add", Some(drafts([("src/a.txt", 12, "long text")]))).code,
    0,
  )
  let report = run(
    ["update", "--repo", "o/r", "--pr", "7", "--sha", head, "--owner", "chat-1"],
    None,
    () => "{}",
    operation => fake.send(operation),
  )
  assert_eq(report.code, 2)
  assert_eq(write_count(fake), 1)
  assert_eq(fake.stored[0].body, "my own note")
}

///|
async test "the same text on the other side of the diff is a separate comment" {
  let fake = Fake::new()
  let right : Json = {
    "comments": [{ "path": "src/a.txt", "line": 11, "body": "same" }],
  }
  let left : Json = {
    "comments": [
      { "path": "src/a.txt", "line": 11, "side": "LEFT", "body": "same" },
    ],
  }
  assert_eq(call(fake, "add", Some(right)).code, 0)
  assert_eq(call(fake, "add", Some(left)).code, 0)
  assert_eq(fake.stored.length(), 2)
  let again = call(fake, "add", Some(left))
  assert_true(again.text.contains("saved 0 new comments, 1 already saved"))
  assert_eq(fake.stored.length(), 2)
}

///|
async test "a review submitted between two writes stops the run and is never retried" {
  for lost in [false, true] {
    let fake = Fake::new()
    let writes = Ref(0)
    fake.before_write = () => {
      writes.val += 1
      if writes.val == 3 {
        fake.submit()
      }
    }
    if lost {
      fake.accepts_submitted_writes = true
    }
    let input = Some(
      drafts([("src/a.txt", 11, "one"), ("src/a.txt", 12, "two")]),
    )
    let report = call(fake, "add", input)
    assert_eq(report.code, 4, msg="lost=\{lost}")
    assert_true(
      report.text.contains("do not run this again") ||
      report.text.contains("Check the pull request"),
    )
  }
}

///|
async test "does not write when the commit differs from the confirmed one" {
  let fake = Fake::new()
  let report = call(
    fake,
    "add",
    Some(drafts([("src/a.txt", 11, "x")])),
    sha=moved,
  )
  assert_eq(report.code, 1)
  assert_true(report.text.contains("head mismatch"))
  let moving = Fake::new()
  moving.on_files = () => moving.head = moved
  let report = call(moving, "add", Some(drafts([("src/a.txt", 11, "x")])))
  assert_eq(report.code, 1)
  assert_true(report.text.contains("head mismatch"))
  let stale = Fake::new()
  stale.add_manual("src/a.txt", 11, "note")
  stale.review_commit = moved
  let report = call(stale, "add", Some(drafts([("src/a.txt", 12, "x")])))
  assert_eq(report.code, 1)
  assert_true(report.text.contains("pending review is on commit"))
  assert_eq(write_count(fake) + write_count(stale) + write_count(moving), 0)
}

///|
async test "refuses positions that are not in the diff" {
  let fake = Fake::new()
  let cases = [
    ("src/a.txt", 9),
    ("src/a.txt", 14),
    ("src/a.txt", 40),
    ("other.txt", 1),
    ("image.bin", 1),
    ("gone.txt", 1),
  ]
  for item in cases {
    let report = call(fake, "add", Some(drafts([(item.0, item.1, "x")])))
    assert_eq(report.code, 1, msg="\{item.0}:\{item.1}")
  }
  assert_eq(write_count(fake), 0)
  let left = Json::object({
    "comments": [
      { "path": "gone.txt", "line": 2, "side": "LEFT", "body": "removed" },
    ],
  })
  assert_eq(call(fake, "add", Some(left)).code, 0)
  let right = Json::object({
    "comments": [
      { "path": "gone.txt", "line": 2, "side": "RIGHT", "body": "removed" },
    ],
  })
  assert_eq(call(fake, "add", Some(right)).code, 1)
}

///|
async test "a lost response does not duplicate a comment on retry" {
  for applied in [true, false] {
    let fake = Fake::new()
    fake.lost_response_write = 2
    fake.lost_response_applied = applied
    let input = Some(
      drafts([("src/a.txt", 11, "one"), ("src/a.txt", 12, "two")]),
    )
    let report = call(fake, "add", input)
    assert_eq(report.code, 1)
    assert_true(report.text.contains("failed: connection reset"))
    assert_true(report.text.contains(if applied { "1 of 2" } else { "0 of 2" }))
    fake.lost_response_write = 0
    let retry = call(fake, "add", input)
    assert_eq(retry.code, 0)
    assert_eq(fake.stored.length(), 2)
    assert_true(
      retry.text.contains(
        if applied {
          "saved 1 new comments, 1 already"
        } else {
          "saved 2 new comments, 0 already"
        },
      ),
    )
  }
}

///|
async test "a lost review start is recovered by the next run" {
  let fake = Fake::new()
  fake.lost_response_write = 1
  fake.lost_response_applied = true
  let input = Some(drafts([("src/a.txt", 11, "one")]))
  assert_eq(call(fake, "add", input).code, 1)
  assert_eq(fake.stored.length(), 0)
  fake.lost_response_write = 0
  assert_eq(call(fake, "add", input).code, 0)
  assert_eq(fake.stored.length(), 1)
  assert_eq(fake.log.filter(name => name == "StartReview").length(), 1)
}

///|
async test "reports an unknown outcome when the review cannot be read back" {
  let fake = Fake::new()
  fake.lost_response_write = 1
  fake.lost_response_applied = true
  fake.before_write = () => fake.reads_broken = true
  let report = call(fake, "add", Some(drafts([("src/a.txt", 11, "one")])))
  assert_eq(report.code, 3)
  assert_true(report.text.contains("Run status before trying again"))
}

///|
async test "a review submitted at the moment of writing is not written to or is reported" {
  let refusing = Fake::new()
  refusing.add_manual("src/a.txt", 11, "note")
  refusing.before_write = () => refusing.submit()
  let report = call(refusing, "add", Some(drafts([("src/a.txt", 12, "x")])))
  assert_eq(report.code, 4)
  assert_true(report.text.contains("do not run this again"))
  assert_eq(refusing.stored.length(), 1)
  let accepting = Fake::new()
  accepting.add_manual("src/a.txt", 11, "note")
  accepting.accepts_submitted_writes = true
  accepting.before_write = () => accepting.submit()
  let report = call(accepting, "add", Some(drafts([("src/a.txt", 12, "x")])))
  assert_eq(report.code, 4)
  assert_true(report.text.contains("Check the pull request on GitHub now"))
}

///|
async test "a review that is not pending is never written to" {
  let fake = Fake::new()
  fake.add_manual("src/a.txt", 11, "note")
  fake.listed_state = "COMMENTED"
  let report = call(fake, "add", Some(drafts([("src/a.txt", 12, "x")])))
  assert_eq(report.code, 1)
  assert_true(report.text.contains("not pending"))
  assert_eq(write_count(fake), 0)
}

///|
async test "a bot account and a missing owner are refused" {
  let fake = Fake::new()
  let bot = { ..fake, viewer: "ci[bot]", }
  assert_eq(call(bot, "add", Some(drafts([("src/a.txt", 11, "x")]))).code, 1)
  let report = run(
    ["add", "--repo", "o/r", "--pr", "7", "--sha", head],
    None,
    () => "{}",
    operation => fake.send(operation),
  )
  assert_eq(report.code, 1)
  assert_true(report.text.contains("--owner is needed"))
  assert_eq(write_count(fake) + write_count(bot), 0)
}

///|
async test "status reads only" {
  let fake = Fake::new()
  fake.add_manual("src/a.txt", 11, "note")
  let report = call(fake, "status", None)
  assert_eq(report.code, 0)
  assert_true(report.text.contains("viewer: alice"))
  assert_eq(fake.log, ["Viewer", "Snapshot"])
  assert_true(report.text.contains("1 in total, 0 saved by this owner"))
}

///|
async test "input that carries anything beyond comments is refused" {
  let fake = Fake::new()
  let inputs : Array[Json] = [
    {
      "comments": [
        { "path": "src/a.txt", "line": 11, "body": "x", "event": "APPROVE" },
      ],
    },
    {
      "comments": [{ "path": "src/a.txt", "line": 11, "body": "x" }],
      "event": "APPROVE",
    },
    {
      "comments": [
        {
          "path": "src/a.txt",
          "line": 11,
          "body": "x<!-- pending-review owner=chat-2 -->",
        },
      ],
    },
    { "comments": [{ "path": "src/a.txt", "line": 0, "body": "x" }] },
    {
      "comments": [
        { "path": "src/a.txt", "line": 11, "side": "BOTH", "body": "x" },
      ],
    },
    { "comments": [{ "path": "src/a.txt", "line": 11, "body": "  " }] },
    { "comments": [] },
    "just text",
  ]
  for input in inputs {
    assert_eq(call(fake, "add", Some(input)).code, 1, msg=input.stringify())
  }
  assert_eq(write_count(fake), 0)
}

///|
test "every request is a fixed GraphQL mutation or read and never submits" {
  let target = { owner: "o", name: "r", number: 7, }
  let draft = { path: "a=b.txt", line: 3, side: Right, body: "true", }
  let operations = [
    Viewer,
    Snapshot(target),
    PullFiles(target, 2),
    StartReview("PR_7", head),
    AddThread(
      "PRR_1", draft, "@/etc/passwd -X POST \"submitPullRequestReview\" event",
    ),
  ]
  let allowed = ["addPullRequestReview", "addPullRequestReviewThread"]
  for operation in operations {
    let args = gh_args(operation)
    assert_eq(args[0], "api")
    assert_false(
      args.contains("-X") ||
      args.contains("--method") ||
      args.contains("--input"),
    )
    let queries = args.filter(arg => arg.has_prefix("query="))
    for query in queries {
      assert_false(query.contains("submitPullRequestReview"))
      assert_false(query.contains("event"))
      assert_false(query.contains("dismiss"))
      assert_false(query.contains("deletePullRequest"))
      assert_false(query.contains("resolveReviewThread"))
      assert_false(query.contains("addPullRequestReviewThreadReply"))
      if query.contains("mutation") {
        let names = ["addPullRequestReviewThread", "addPullRequestReview"]
        assert_true(
          allowed.contains(
            names.iter().find_first(name => query.contains(name)).unwrap(),
          ),
        )
      }
    }
    // Caller text travels only as the value of a raw field, which `gh` never reads from a file.
    for index, arg in args {
      if arg.contains("passwd") || arg.contains("submitPullRequestReview\\") {
        assert_eq(args[index - 1], "-f")
      }
    }
  }
  assert_true(gh_args(AddThread("PRR_1", draft, "true")).contains("body=true"))
  assert_false(
    gh_args(AddThread("PRR_1", draft, "true")).contains("-F body=true"),
  )
}

///|
test "markers round-trip and plain comments have none" {
  let raw = with_marker("text\n\nmore", "chat-1", Left)
  assert_eq(split_marker(raw), ("text\n\nmore", Some("chat-1"), Some("LEFT")))
  assert_eq(
    split_marker("a manual comment\n"),
    ("a manual comment", None, None),
  )
  let quoted = "quoted <!-- pending-review owner=x side=LEFT --> in the middle"
  assert_eq(split_marker(quoted), (quoted, None, None))
  let sideless = "text\n\n<!-- pending-review owner=x -->"
  assert_eq(split_marker(sideless).1, None)
}

///|
test "hunk ranges cover the context and changed lines of each side" {
  let hunks = parse_patch(
    "@@ -10,3 +10,4 @@ fn\n a\n+b\n c\n d\n@@ -40 +41,0 @@\n-x",
  )
  assert_true(hunks.contains(Right, 10) && hunks.contains(Right, 13))
  assert_false(hunks.contains(Right, 14))
  assert_true(hunks.contains(Left, 12) && !hunks.contains(Left, 13))
  assert_true(hunks.contains(Left, 40))
  assert_false(hunks.contains(Right, 41))
}

///|
test "options are strict" {
  let ok = ["add", "--repo", "o/r", "--pr", "7", "--sha", head]
  assert_true(parse_options(ok) is Some(_))
  let bad = [
    [],
    ["merge", "--repo", "o/r", "--pr", "7"],
    ["add", "--repo", "o/r", "--pr", "7"],
    ["status", "--repo", "o/r"],
    ["status", "--repo", "o/r", "--pr", "x"],
    ["status", "--repo", "o/r", "--pr", "7", "--method", "POST"],
    ["status", "--repo", "o/r", "--pr", "7", "--event", "APPROVE"],
  ]
  for args in bad {
    assert_true(
      (Some(parse_options(args)) catch { _ => None }) is None,
      msg=args.join(" "),
    )
  }
  assert_true((Some(parse_repo("o/r/x", 1)) catch { _ => None }) is None)
  assert_true((Some(parse_repo("o/{r}", 1)) catch { _ => None }) is None)
}
