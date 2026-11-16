///|
let head : String = "1111111111111111111111111111111111111111"

///|
let moved : String = "2222222222222222222222222222222222222222"

///|
priv struct Stored {
  id : String
  path : String
  line : Int32
  mut body : String
}

///|
priv struct Fake {
  mut head : String
  mut review : String?
  mut review_commit : String
  stored : Array[Stored]
  mut writes : Int32
  mut lost_response_write : Int32
  mut lost_response_applied : Bool
  mut reads_broken : Bool
  mut breaks_reads_on_write : Bool
  mut on_files : () -> Unit
  mut listed_state : String
  mut viewer : String
}

///|
fn Fake::new() -> Fake {
  {
    head,
    review: None,
    review_commit: head,
    stored: [],
    writes: 0,
    lost_response_write: 0,
    lost_response_applied: false,
    reads_broken: false,
    breaks_reads_on_write: false,
    on_files: () => (),
    listed_state: "PENDING",
    viewer: "alice",
  }
}

///|
fn Fake::manual(
  self : Fake,
  path : String,
  line : Int32,
  body : String,
) -> Unit {
  self.review = Some("PRR_1")
  self.stored.push({ id: "PRRC_\{self.stored.length() + 1}", path, line, body, })
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
    "body": stored.body,
  })
  fn review(id : String, login : String, comments : Array[Json]) -> Json {
    let node : Json = {
      "id": id,
      "state": self.listed_state,
      "url": "https://github.com/o/r/pull/7#pullrequestreview-9",
      "author": { "login": login },
      "commit": { "oid": self.review_commit },
      "comments": { "pageInfo": { "hasNextPage": false }, "nodes": comments },
    }
    node
  }
  let nodes : Array[Json] = match self.review {
    None => []
    Some(id) => [review(id, self.viewer, comments), review("x", "mallory", [])]
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
  if self.breaks_reads_on_write {
    self.reads_broken = true
  }
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
      if self.review != Some(review_id) {
        raise Api("Could not resolve to a pending review")
      }
      let id = "PRRC_\{self.stored.length() + 1}"
      self.stored.push({ id, path: draft.path, line: draft.line, body, })
      let node : Json = { "id": id, "state": "PENDING" }
      {
        "data": {
          "addPullRequestReviewThread": {
            "thread": { "comments": { "nodes": [node] } },
          },
        },
      }
    }
    EditComment(id, body) =>
      match self.stored.iter().find_first(stored => stored.id == id) {
        Some(stored) => {
          stored.body = body
          { "data": {} }
        }
        None => raise Api("Could not resolve to a node")
      }
    _ => raise Api("not a write")
  }
}

///|
fn comment(
  path : String,
  line : Int32,
  body : String,
  side~ : String = "RIGHT",
) -> Json {
  { "path": path, "line": line, "side": side, "body": body }
}

///|
async fn send(fake : Fake, request : Json) -> Report {
  run(request.stringify(), None, operation => fake.send(operation))
}

///|
async fn call(
  fake : Fake,
  add~ : Array[Json] = [],
  update~ : Array[Json] = [],
  sha~ : String = head,
  owner~ : String = "chat-1",
) -> Report {
  let request : Json = {
    "repo": "o/r",
    "pr": 7,
    "sha": sha,
    "owner": owner,
    "add": add,
    "update": update,
  }
  send(fake, request)
}

///|
async test "saves comments into a new pending review at the confirmed commit" {
  let fake = Fake::new()
  let first = comment("src/a.txt", 11, "first\nsecond")
  let report = call(fake, add=[first, comment("src/a.txt", 41, "again")])
  assert_eq(report.code, 0)
  assert_true(report.text.contains("saved 2 new, 0 already saved, edited 0"))
  assert_true(
    report.text.contains("pending review: PENDING https://github.com"),
  )
  assert_true(report.text.contains("  PRRC_1  src/a.txt:11"))
  assert_eq(fake.review_commit, head)
  assert_eq(
    fake.stored[0].body,
    "first\nsecond\n\n<!-- pending-review owner=chat-1 side=RIGHT -->",
  )
}

///|
async test "leaves comments it did not save alone, and edits only its own" {
  let fake = Fake::new()
  fake.manual("src/a.txt", 11, "my own note")
  assert_eq(call(fake, add=[comment("src/a.txt", 12, "long text")]).code, 0)
  let other = call(fake, add=[comment("src/a.txt", 13, "x")], owner="chat-2")
  assert_eq(other.code, 0)
  let writes = fake.writes
  for id in ["PRRC_1", "PRRC_3", "PRRC_404"] {
    let report = call(fake, update=[{ "id": id, "body": "rewritten" }])
    assert_eq(report.code, 1, msg=id)
  }
  assert_eq(fake.writes, writes)
  let edit : Json = { "id": "PRRC_2", "body": "short" }
  assert_eq(call(fake, update=[edit]).code, 0)
  assert_eq(
    fake.stored[1].body,
    "short\n\n<!-- pending-review owner=chat-1 side=RIGHT -->",
  )
  assert_eq(fake.stored[0].body, "my own note")
  assert_true(call(fake, update=[edit]).text.contains("edited 0"))
  assert_eq(fake.writes, writes + 1)
}

///|
async test "the other side of the diff is a separate comment, and reruns add nothing" {
  let fake = Fake::new()
  let right = comment("src/a.txt", 11, "same")
  let left = comment("src/a.txt", 11, "same", side="LEFT")
  assert_eq(call(fake, add=[right, left, right]).code, 0)
  assert_eq(fake.stored.length(), 2)
  let again = call(fake, add=[right, left, right])
  assert_true(again.text.contains("saved 0 new, 3 already saved"))
  assert_eq(fake.stored.length(), 2)
}

///|
async test "does not write when the commit differs from the confirmed one" {
  let x = comment("src/a.txt", 11, "x")
  let wrong = Fake::new()
  assert_eq(call(wrong, add=[x], sha=moved).code, 1)
  let moving = Fake::new()
  moving.on_files = () => moving.head = moved
  assert_eq(call(moving, add=[x]).code, 1)
  let stale = Fake::new()
  stale.manual("src/a.txt", 11, "note")
  stale.review_commit = moved
  assert_eq(call(stale, add=[x]).code, 1)
  assert_eq(wrong.writes + moving.writes + stale.writes, 0)
}

///|
async test "refuses positions that are not in the diff" {
  let fake = Fake::new()
  let positions = [
    ("src/a.txt", 9),
    ("src/a.txt", 14),
    ("src/a.txt", 40),
    ("other.txt", 1),
    ("image.bin", 1),
    ("gone.txt", 1),
  ]
  for position in positions {
    let report = call(fake, add=[comment(position.0, position.1, "x")])
    assert_eq(report.code, 1, msg="\{position.0}:\{position.1}")
  }
  assert_eq(fake.writes, 0)
  let removed = comment("gone.txt", 2, "removed", side="LEFT")
  assert_eq(call(fake, add=[removed]).code, 0)
}

///|
async test "a lost response does not duplicate a comment on retry" {
  for applied in [true, false] {
    let fake = Fake::new()
    fake.lost_response_write = 2
    fake.lost_response_applied = applied
    let input = [
      comment("src/a.txt", 11, "one"),
      comment("src/a.txt", 12, "two"),
    ]
    assert_eq(call(fake, add=input).code, 1)
    fake.lost_response_write = 0
    assert_eq(call(fake, add=input).code, 0)
    assert_eq(fake.stored.length(), 2)
  }
}

///|
async test "a lost review start is recovered by the next run" {
  let fake = Fake::new()
  fake.lost_response_write = 1
  fake.lost_response_applied = true
  let input = [comment("src/a.txt", 11, "one")]
  assert_eq(call(fake, add=input).code, 1)
  fake.lost_response_write = 0
  assert_eq(call(fake, add=input).code, 0)
  assert_eq(fake.stored.length(), 1)
}

///|
async test "reports an unknown outcome when the review cannot be read back" {
  let fake = Fake::new()
  fake.lost_response_write = 1
  fake.lost_response_applied = true
  fake.breaks_reads_on_write = true
  assert_eq(call(fake, add=[comment("src/a.txt", 11, "one")]).code, 3)
}

///|
async test "a review that is not pending and a bot account are never written to" {
  let x = comment("src/a.txt", 12, "x")
  let fake = Fake::new()
  fake.manual("src/a.txt", 11, "note")
  fake.listed_state = "COMMENTED"
  let bot = Fake::new()
  bot.viewer = "ci[bot]"
  assert_eq(call(fake, add=[x]).code, 1)
  assert_eq(call(bot, add=[x]).code, 1)
  assert_eq(fake.writes + bot.writes, 0)
}

///|
async test "an empty request only reads the state" {
  let fake = Fake::new()
  fake.manual("src/a.txt", 11, "note")
  let report = call(fake)
  assert_eq(report.code, 0)
  assert_true(report.text.contains("viewer: alice"))
  assert_eq(fake.writes, 0)
}

///|
async test "input beyond the fixed fields is refused" {
  let fake = Fake::new()
  let changes : Array[(String, Json)] = [
    ("event", "APPROVE"),
    ("add", [{ "path": "src/a.txt", "line": 11, "body": "x", "event": "A" }]),
    ("add", [comment("src/a.txt", 11, "x<!-- pending-review owner=c -->")]),
    ("add", [comment("src/a.txt", 0, "x")]),
    ("add", [comment("src/a.txt", 11, "x", side="BOTH")]),
    ("add", [comment("src/a.txt", 11, "  ")]),
    ("sha", "abc"),
    ("repo", "o/r/x"),
    ("repo", "o/{r}"),
    ("pr", 0),
    ("owner", "bad owner"),
  ]
  for change in changes {
    let request : Map[String, Json] = {
      "repo": "o/r",
      "pr": 7,
      "sha": head,
      "owner": "chat-1",
    }
    request[change.0] = change.1
    let report = send(fake, Json::object(request))
    assert_eq(report.code, 1, msg=change.0)
  }
  assert_eq(run("not json", None, op => fake.send(op)).code, 1)
  let no_owner : Json = { "repo": "o/r", "pr": 7, "sha": head }
  let no_owner = no_owner.stringify()
  assert_eq(run(no_owner, None, op => fake.send(op)).code, 1)
  assert_eq(fake.writes, 0)
}

///|
test "every request is a fixed GraphQL mutation or read and never submits" {
  let target = { owner: "o", name: "r", number: 7, }
  let draft = { path: "a=b.txt", line: 3, side: Right, body: "true", }
  let hostile = "@/etc/passwd -X POST submitPullRequestReview event"
  let operations = [
    Viewer,
    Snapshot(target),
    PullFiles(target, 2),
    StartReview("PR_7", head),
    AddThread("PRR_1", draft, hostile),
    EditComment("PRRC_1", hostile),
  ]
  let allowed = [
    "addPullRequestReview", "addPullRequestReviewThread", "updatePullRequestReviewComment",
  ]
  let forbidden = [
    "submitPullRequestReview", "event", "dismiss", "deletePullRequest", "resolveReviewThread",
    "ThreadReply",
  ]
  for operation in operations {
    let args = gh_args(operation)
    assert_eq(args[0], "api")
    assert_false(
      args.contains("-X") ||
      args.contains("--method") ||
      args.contains("--input"),
    )
    for query in args.filter(arg => arg.has_prefix("query=")) {
      for word in forbidden {
        assert_false(query.contains(word), msg=word)
      }
      if query.contains("mutation") {
        assert_true(allowed.iter().any(name => query.contains("\{name}(")))
      }
    }
    // Caller text travels only as the value of a raw field, which `gh` never reads from a file.
    for index, arg in args {
      if arg.contains("passwd") {
        assert_eq(args[index - 1], "-f")
      }
    }
  }
}

///|
test "markers round-trip and plain comments have none" {
  let raw = with_marker("text\n\nmore", "chat-1", "LEFT")
  assert_eq(split_marker(raw), ("text\n\nmore", Some("chat-1"), Some("LEFT")))
  assert_eq(
    split_marker("a manual comment\n"),
    ("a manual comment", None, None),
  )
  let quoted = "quoted <!-- pending-review owner=x side=LEFT --> in the middle"
  assert_eq(split_marker(quoted), (quoted, None, None))
  assert_eq(split_marker("text\n\n<!-- pending-review owner=x -->").1, None)
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
