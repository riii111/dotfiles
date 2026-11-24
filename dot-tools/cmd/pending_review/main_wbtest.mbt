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
  thread : String?
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
  mut on_thread : () -> Unit
  mut listed_state : String
  mut reply_state : String
  mut published_comments : Int32
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
    on_thread: () => (),
    listed_state: "PENDING",
    reply_state: "PENDING",
    published_comments: 0,
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
  self.stored.push({
    id: "PRRC_\{self.stored.length() + 1}",
    path,
    line,
    body,
    thread: None,
  })
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
      "comments": {
        "pageInfo": { "hasNextPage": comments.length() > 100 },
        "nodes": comments,
      },
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
    Thread(id, after) => {
      if self.reads_broken {
        raise Api("connection reset")
      }
      let all : Array[Json] = []
      for index in 0..<self.published_comments {
        all.push({ "id": "published-\{index}" })
      }
      let pending : Array[Json] = self.stored
        .filter(item => item.thread == Some(id))
        .map(item => { "id": item.id })
      for item in pending {
        all.push(item)
      }
      let start = match after {
        None => 0
        Some(cursor) => parse_number(cursor).unwrap_or(0)
      }
      let end = if start + 100 < all.length() {
        start + 100
      } else {
        all.length()
      }
      let nodes : Array[Json] = []
      for index in start..<end {
        nodes.push(all[index])
      }
      let has_next = end < all.length() || id == "large" || id == "loop"
      let cursor : Json = if id == "large" {
        Json::null()
      } else if id == "loop" {
        Json::string("0")
      } else {
        Json::string("\{end}")
      }
      let pull = if id == "other" { "PR_other" } else { "PR_7" }
      let response : Json = {
        "data": {
          "node": {
            "id": id,
            "pullRequest": { "id": pull },
            "viewerCanReply": id != "blocked",
            "comments": {
              "pageInfo": { "hasNextPage": has_next, "endCursor": cursor },
              "nodes": nodes,
            },
          },
        },
      }
      (self.on_thread)()
      return response
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
      self.stored.push({
        id,
        path: draft.path,
        line: draft.line,
        body,
        thread: None,
      })
      let node : Json = { "id": id, "state": "PENDING" }
      {
        "data": {
          "addPullRequestReviewThread": {
            "thread": { "comments": { "nodes": [node] } },
          },
        },
      }
    }
    AddReply(review_id, thread, body) => {
      if self.review != Some(review_id) {
        raise Api("Could not resolve to a pending review")
      }
      let id = "PRRC_\{self.stored.length() + 1}"
      self.stored.push({
        id,
        path: "src/a.txt",
        line: 11,
        body,
        thread: Some(thread),
      })
      {
        "data": {
          "addPullRequestReviewThreadReply": {
            "comment": { "id": id, "state": self.reply_state },
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
  level~ : String = "[Q] ",
) -> Json {
  { "path": path, "line": line, "side": side, "body": level + body }
}

///|
async fn send(fake : Fake, request : Json) -> Report {
  run(request.stringify(), None, operation => fake.send(operation))
}

///|
async fn call(
  fake : Fake,
  add~ : Array[Json] = [],
  reply~ : Array[Json] = [],
  update~ : Array[Json] = [],
  sha~ : String = head,
  owner~ : String? = Some("chat-1"),
) -> Report {
  let request : Map[String, Json] = {
    "repo": "o/r",
    "pr": 7,
    "sha": sha,
    "add": Json::array(add),
    "reply": Json::array(reply),
    "update": Json::array(update),
  }
  if owner is Some(owner) {
    request["owner"] = Json::string(owner)
  }
  send(fake, Json::object(request))
}

///|
async test "replies stay in the requested thread and pending review, retry without duplicates, and remain editable" {
  let fake = Fake::new()
  let one : Json = { "thread": "thread-1", "body": "ありがとう" }
  let two : Json = { "thread": "thread-2", "body": "ありがとう" }
  fake.lost_response_write = 2
  fake.lost_response_applied = true
  assert_eq(call(fake, reply=[one, two, one]).code, 1)
  fake.lost_response_write = 0
  assert_eq(call(fake, reply=[one, two, one]).code, 0)
  assert_eq(fake.stored.length(), 2)
  assert_eq(fake.stored[0].thread, Some("thread-1"))
  assert_eq(fake.stored[1].thread, Some("thread-2"))
  let edit : Json = { "id": "PRRC_1", "body": "確認しました" }
  assert_eq(call(fake, update=[edit], owner=None).code, 0)
  assert_eq(
    fake.stored[0].body,
    "確認しました\n\n<!-- pending-review owner=chat-1 side=REPLY -->",
  )
  assert_eq(call(fake, reply=[two]).code, 0)
  assert_eq(fake.stored.length(), 2)
}

///|
async test "refuses replies to another PR, inaccessible threads, stale heads and incomplete thread reads before writing" {
  for thread in ["other", "blocked"] {
    let fake = Fake::new()
    let reply : Json = { "thread": thread, "body": "thanks" }
    assert_eq(call(fake, reply=[reply]).code, 1)
    assert_eq(fake.writes, 0)
  }
  let broken = Fake::new()
  let incomplete : Json = { "thread": "large", "body": "thanks" }
  assert_eq(call(broken, reply=[incomplete]).code, 3)
  assert_eq(broken.writes, 0)
  let repeated : Json = { "thread": "loop", "body": "thanks" }
  assert_eq(call(broken, reply=[repeated]).code, 3)
  assert_eq(broken.writes, 0)
  let fake = Fake::new()
  let reply : Json = { "thread": "thread-1", "body": "thanks" }
  assert_eq(call(fake, reply=[reply], sha=moved).code, 1)
  assert_eq(fake.writes, 0)
}

///|
async test "reads across the page boundary after saving and on retry" {
  let success = Fake::new()
  success.published_comments = 100
  let reply : Json = { "thread": "thread-1", "body": "thanks" }
  assert_eq(call(success, reply=[reply]).code, 0)
  assert_eq(call(success, reply=[reply]).code, 0)
  assert_eq(success.stored.length(), 1)
  let fake = Fake::new()
  fake.published_comments = 100
  fake.lost_response_write = 2
  fake.lost_response_applied = true
  let result = call(fake, reply=[reply])
  assert_eq(result.code, 1)
  assert_true(result.text.contains("1 of 1 changes are on the server"))
  fake.lost_response_write = 0
  assert_eq(call(fake, reply=[reply]).code, 0)
  assert_eq(fake.stored.length(), 1)
}

///|
async test "does not duplicate a reply that appears between the thread and review reads" {
  let fake = Fake::new()
  fake.review = Some("PRR_1")
  let reply : Json = { "thread": "thread-1", "body": "thanks" }
  fake.lost_response_write = 1
  let first = call(fake, reply=[reply])
  assert_eq(first.code, 1)
  assert_true(first.text.contains("0 of 1 changes are on the server"))
  fake.lost_response_write = 0
  fake.on_thread = () => {
    fake.on_thread = () => ()
    fake.stored.push({
      id: "PRRC_1",
      path: "src/a.txt",
      line: 11,
      body: with_marker("thanks", "chat-1", "REPLY"),
      thread: Some("thread-1"),
    })
  }
  assert_eq(call(fake, reply=[reply]).code, 3)
  assert_eq(fake.writes, 1)
  assert_eq(fake.stored.length(), 1)
  assert_eq(call(fake, reply=[reply]).code, 0)
  assert_eq(fake.writes, 1)
}

///|
async test "allows the same text in a different thread when the existing reply was already observed" {
  let fake = Fake::new()
  let first : Json = { "thread": "thread-1", "body": "thanks" }
  let second : Json = { "thread": "thread-2", "body": "thanks" }
  assert_eq(call(fake, reply=[first]).code, 0)
  assert_eq(call(fake, reply=[second]).code, 0)
  assert_eq(fake.stored.length(), 2)
}

///|
async test "refuses additions that would make the pending review unreadable" {
  let fake = Fake::new()
  for index in 0..<100 {
    fake.manual("src/a.txt", 11, "manual \{index}")
  }
  let reply : Json = { "thread": "thread-1", "body": "thanks" }
  assert_eq(call(fake, reply=[reply]).code, 1)
  assert_eq(fake.writes, 0)
  assert_eq(fake.stored.length(), 100)
}

///|
async test "rejects adding and changing the same saved comment before any write" {
  let fake = Fake::new()
  let reply : Json = { "thread": "thread-1", "body": "old" }
  assert_eq(call(fake, reply=[reply]).code, 0)
  let edit : Json = { "id": "PRRC_1", "body": "new" }
  let writes = fake.writes
  assert_eq(call(fake, reply=[reply], update=[edit]).code, 1)
  assert_eq(fake.writes, writes)
  assert_eq(call(fake, reply=[reply], update=[edit]).code, 1)
  assert_eq(fake.stored.length(), 1)
  assert_true(fake.stored[0].body.contains("old"))
  let line = Fake::new()
  let draft = comment("src/a.txt", 11, "old")
  assert_eq(call(line, add=[draft]).code, 0)
  let line_edit : Json = { "id": "PRRC_1", "body": "[Q] new" }
  let line_writes = line.writes
  assert_eq(call(line, add=[draft], update=[line_edit]).code, 1)
  assert_eq(line.writes, line_writes)
}

///|
async test "a reply with an unconfirmed state requires inspection and an unapplied request can be retried" {
  let reply : Json = { "thread": "thread-1", "body": "thanks" }
  let unknown = Fake::new()
  unknown.reply_state = "COMMENTED"
  assert_eq(call(unknown, reply=[reply]).code, 3)
  let retry = Fake::new()
  retry.lost_response_write = 2
  assert_eq(call(retry, reply=[reply]).code, 1)
  retry.lost_response_write = 0
  assert_eq(call(retry, reply=[reply]).code, 0)
  assert_eq(retry.stored.length(), 1)
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
    "[Q] first\nsecond\n\n<!-- pending-review owner=chat-1 side=RIGHT -->",
  )
}

///|
async test "any chat edits any comment of the user's pending review and keeps its marker" {
  let fake = Fake::new()
  fake.manual("src/a.txt", 11, "my own note")
  assert_eq(call(fake, add=[comment("src/a.txt", 12, "long text")]).code, 0)
  let state = call(fake, owner=None)
  assert_true(state.text.contains("  PRRC_1  src/a.txt:11  handwritten"))
  assert_true(state.text.contains("  PRRC_2  src/a.txt:12  owner=chat-1"))
  assert_true(state.text.contains("    | [Q] long text"))
  let writes = fake.writes
  let refused : Array[Json] = [
    { "id": "PRRC_404", "body": "[Q] rewritten" },
    { "id": "PRRC_2", "body": "unlabeled" },
  ]
  for edit in refused {
    assert_eq(call(fake, update=[edit], owner=None).code, 1)
  }
  assert_eq(fake.writes, writes)
  let edit : Json = { "id": "PRRC_2", "body": "[nits] short" }
  assert_eq(call(fake, update=[edit], owner=Some("side-chat")).code, 0)
  assert_eq(
    fake.stored[1].body,
    "[nits] short\n\n<!-- pending-review owner=chat-1 side=RIGHT -->",
  )
  let manual : Json = { "id": "PRRC_1", "body": "my own, tidied note" }
  assert_eq(call(fake, update=[manual], owner=None).code, 0)
  assert_eq(fake.stored[0].body, "my own, tidied note")
  assert_true(call(fake, update=[edit]).text.contains("edited 0"))
  assert_eq(fake.writes, writes + 2)
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
    ("add", [comment("src/a.txt", 11, "  ", level="")]),
    ("add", [comment("src/a.txt", 11, "x", level="")]),
    ("add", [comment("src/a.txt", 11, "x", level="[major] ")]),
    ("add", [comment("src/a.txt", 11, "x", level="[Q]")]),
    ("reply", [{ "thread": "", "body": "thanks" }]),
    ("reply", [{ "thread": "thread", "body": "thanks", "event": "COMMENT" }]),
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
  let x = comment("src/a.txt", 11, "x")
  assert_eq(call(fake, add=[x], owner=None).code, 1)
  assert_eq(call(fake, owner=None).code, 0)
  assert_eq(fake.writes, 0)
}

///|
test "every request is a fixed GraphQL mutation or read and never submits" {
  let target = { owner: "o", name: "r", number: 7, }
  let draft = { path: "a=b.txt", line: 3, side: Right, body: "true", }
  let hostile = "@/etc/passwd -X POST submitPullRequestReview event"
  let reply_args = gh_args(AddReply("PRR_1", "PRRT_1", hostile))
  assert_true(reply_args.contains("review=PRR_1"))
  assert_true(reply_args.contains("thread=PRRT_1"))
  assert_true(add_reply_query.contains("pullRequestReviewId: $review"))
  assert_true(add_reply_query.contains("pullRequestReviewThreadId: $thread"))
  let operations = [
    Viewer,
    Snapshot(target),
    PullFiles(target, 2),
    Thread("thread", None),
    Thread("thread", Some("cursor")),
    StartReview("PR_7", head),
    AddThread("PRR_1", draft, hostile),
    AddReply("PRR_1", "thread", hostile),
    EditComment("PRRC_1", hostile),
  ]
  let allowed = [
    "addPullRequestReview", "addPullRequestReviewThread", "addPullRequestReviewThreadReply",
    "updatePullRequestReviewComment",
  ]
  let forbidden = [
    "submitPullRequestReview", "event", "dismiss", "deletePullRequest", "resolveReviewThread",
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
