///|
priv struct Session {
  send : async (Operation) -> Json raise Failure
  target : Target
}

///|
priv struct Report {
  text : String
  code : Int32
}

///|
async fn Session::viewer(self : Session) -> String raise Failure {
  let json = (self.send)(Viewer)
  let login = required_text(json.field("data").field("viewer"), "login")
  if login.has_suffix("[bot]") {
    raise Refused(
      "\{login} is a bot account; the review would not be the user's own",
    )
  }
  login
}

///|
async fn Session::pull(self : Session, viewer : String) -> Pull raise Failure {
  parse_pull((self.send)(Snapshot(self.target)), viewer)
}

///|
async fn Session::diff(self : Session) -> Map[String, Hunks?] raise Failure {
  let files = Map([])
  for page in 1..<31 {
    let json = (self.send)(PullFiles(self.target, page))
    guard json is Array(entries) else {
      raise Refused("GitHub returned an unexpected file list")
    }
    for path, hunks in parse_files(entries) {
      files[path] = hunks
    }
    if entries.length() < 100 {
      return files
    }
  }
  raise Refused("too many changed files to check the comment positions")
}

///|
async fn Session::threads(
  self : Session,
  replies : Array[Reply],
  pull_id : String,
) -> Map[String, Array[String]] raise Failure {
  let threads : Map[String, Array[String]] = Map([])
  for reply in replies {
    if threads.contains(reply.thread) {
      continue
    }
    let ids = []
    let cursors : Array[String] = []
    let mut after : String? = None
    while true {
      let node = (self.send)(Thread(reply.thread, after))
        .field("data")
        .field("node")
      if node.field("id").text() != Some(reply.thread) ||
        node.field("pullRequest").field("id").text() != Some(pull_id) {
        raise Refused(
          "thread \{reply.thread} is not in the target pull request",
        )
      }
      if !node.field("viewerCanReply").flag() {
        raise Refused("cannot reply to thread \{reply.thread}")
      }
      let comments = node.field("comments")
      let page = comments.field("pageInfo")
      guard comments.field("nodes") is Array(_) &&
        page.field("hasNextPage") is (True | False) else {
        raise Unverified(
          "thread \{reply.thread} has an incomplete comment list",
        )
      }
      for comment in comments.field("nodes").items() {
        ids.push(required_text(comment, "id"))
      }
      if !page.field("hasNextPage").flag() {
        break
      }
      guard page.field("endCursor").text() is Some(cursor) &&
        !cursor.is_empty() &&
        !cursors.contains(cursor) else {
        raise Unverified("thread \{reply.thread} has an invalid page cursor")
      }
      cursors.push(cursor)
      after = Some(cursor)
    }
    threads[reply.thread] = ids
  }
  threads
}

///|
fn short(sha : String) -> String {
  if sha.length() > 7 {
    sha[:7].to_owned()
  } else {
    sha
  }
}

///|
fn check_pull(pull : Pull, sha : String) -> Unit raise Failure {
  if pull.state != "OPEN" {
    raise Refused("the pull request is \{pull.state}")
  }
  if pull.head != sha {
    raise Refused(
      "head mismatch: confirmed \{short(sha)} but the pull request is at \{short(pull.head)}",
    )
  }
  if pull.review is Some(review) && review.commit != pull.head {
    raise Refused(
      "the pending review is on commit \{short(review.commit)}, not the head \{short(pull.head)}; submit or discard it on GitHub first",
    )
  }
}

///|
fn is_saved(comment : Comment, owner : String, draft : Draft) -> Bool {
  comment.owner == Some(owner) &&
  comment.side == Some(draft.side.name()) &&
  comment.path == draft.path &&
  comment.line == draft.line &&
  comment.text == draft.body
}

///|
fn comments_of(pull : Pull) -> Array[Comment] {
  match pull.review {
    Some(review) => review.comments
    None => []
  }
}

///|
fn preview(text : String) -> String {
  let output = StringBuilder()
  for char in text.replace_all(old="\n", new=" ").iter().take(60) {
    output.write_char(char)
  }
  output.to_string()
}

///|
fn render(session : Session, viewer : String, pull : Pull) -> String {
  let target = session.target
  let lines = [
    "viewer: \{viewer}",
    "pull request: \{target.owner}/\{target.name}#\{target.number} \{pull.state} head \{short(pull.head)} \{pull.url}",
  ]
  match pull.review {
    None => lines.push("pending review: none")
    Some(review) => {
      lines.push("pending review: PENDING \{review.url}")
      lines.push("comments: \{review.comments.length()}")
      for comment in review.comments {
        let origin = match comment.owner {
          Some(owner) => "owner=\{owner}"
          None => "handwritten"
        }
        lines.push(
          "  \{comment.id}  \{comment.path}:\{comment.line}  \{origin}",
        )
        for text in comment.text.split("\n") {
          lines.push("    | \{text}")
        }
      }
    }
  }
  lines.push("This command cannot submit the review; submit it on GitHub.")
  lines.join("\n") + "\n"
}

///|
async fn start_review(
  session : Session,
  pull : Pull,
  sha : String,
) -> String raise Failure {
  let json = (session.send)(StartReview(pull.id, sha))
  let review = json
    .field("data")
    .field("addPullRequestReview")
    .field("pullRequestReview")
  if review.field("state").text() != Some("PENDING") {
    raise Unverified("GitHub did not report the new review as pending")
  }
  required_text(review, "id")
}

///|
async fn save_draft(
  session : Session,
  review_id : String,
  draft : Draft,
  owner : String,
) -> Unit raise Failure {
  let body = with_marker(draft.body, owner, draft.side.name())
  let json = (session.send)(AddThread(review_id, draft, body))
  let comments = json
    .field("data")
    .field("addPullRequestReviewThread")
    .field("thread")
    .field("comments")
    .field("nodes")
    .items()
  if comments
    .iter()
    .any(comment => comment.field("state").text() != Some("PENDING")) {
    raise Unverified("GitHub did not report a saved comment as pending")
  }
}

///|
async fn save_reply(
  session : Session,
  review_id : String,
  reply : Reply,
  owner : String,
) -> Unit raise Failure {
  let json = (session.send)(
    AddReply(review_id, reply.thread, with_marker(reply.body, owner, "REPLY")),
  )
  let comment = json
    .field("data")
    .field("addPullRequestReviewThreadReply")
    .field("comment")
  if comment.field("state").text() != Some("PENDING") ||
    comment.field("id").text() is None {
    raise Unverified("GitHub did not report the reply as pending")
  }
}

///|
fn reply_saved(
  pull : Pull,
  threads : Map[String, Array[String]],
  owner : String,
  reply : Reply,
) -> Bool {
  let ids = threads.get(reply.thread).unwrap_or([])
  comments_of(pull)
  .iter()
  .any(comment => {
    ids.contains(comment.id) &&
    comment.owner == Some(owner) &&
    comment.side == Some("REPLY") &&
    comment.text == reply.body
  })
}

///|
fn replies_to_save(
  pull : Pull,
  threads : Map[String, Array[String]],
  owner : String,
  replies : Array[Reply],
) -> Array[Reply] {
  let todo : Array[Reply] = []
  for reply in replies {
    if !reply_saved(pull, threads, owner, reply) &&
      !todo
      .iter()
      .any(other => other.thread == reply.thread && other.body == reply.body) {
      todo.push(reply)
    }
  }
  todo
}

///|
fn find_comment(pull : Pull, id : String) -> Comment? {
  comments_of(pull).iter().find_first(comment => comment.id == id)
}

///|
fn edits_to_make(
  pull : Pull,
  edits : Array[Edit],
) -> Array[(Edit, Comment)] raise Failure {
  let todo = []
  for edit in edits {
    // The snapshot holds only the viewer's own pending review, so any comment found in it is the user's own draft.
    guard find_comment(pull, edit.id) is Some(comment) else {
      raise Refused("\{edit.id} is not a comment in your pending review")
    }
    // Replies and handwritten comments keep their own style, so only saved line comments need a level.
    if comment.owner is Some(_) && comment.side != Some("REPLY") {
      check_level(edit.body)
    }
    if comment.text != edit.body {
      todo.push((edit, comment))
    }
  }
  todo
}

///|
fn edited_body(edit : Edit, comment : Comment) -> String {
  match (comment.owner, comment.side) {
    (Some(owner), Some(side)) => with_marker(edit.body, owner, side)
    _ => edit.body
  }
}

///|
fn check_add_edit_conflicts(
  drafts : Array[Draft],
  replies : Array[Reply],
  threads : Map[String, Array[String]],
  owner : String,
  edits : Array[(Edit, Comment)],
) -> Unit raise Failure {
  for item in edits {
    let comment = item.1
    let matches_draft = drafts
      .iter()
      .any(draft => is_saved(comment, owner, draft))
    let matches_reply = replies
      .iter()
      .any(reply => {
        threads.get(reply.thread).unwrap_or([]).contains(comment.id) &&
        comment.owner == Some(owner) &&
        comment.side == Some("REPLY") &&
        comment.text == reply.body
      })
    if matches_draft || matches_reply {
      raise Refused(
        "\{comment.id} is both an addition and an update; submit them separately",
      )
    }
  }
}

///|
fn drafts_to_save(
  pull : Pull,
  owner : String,
  drafts : Array[Draft],
) -> Array[Draft] {
  let todo : Array[Draft] = []
  for draft in drafts {
    let saved = comments_of(pull)
      .iter()
      .any(comment => is_saved(comment, owner, draft))
    let queued = todo
      .iter()
      .any(other => {
        other.path == draft.path &&
        other.line == draft.line &&
        other.side.name() == draft.side.name() &&
        other.body == draft.body
      })
    if !saved && !queued {
      todo.push(draft)
    }
  }
  todo
}

///|
async fn run_request(
  session : Session,
  request : Request,
) -> Report raise Failure {
  let { sha, owner, drafts, replies, edits, .. } = request
  let viewer = session.viewer()
  let initial = session.pull(viewer)
  check_pull(initial, sha)
  let files = if drafts.is_empty() { Map([]) } else { session.diff() }
  let threads = session.threads(replies, initial.id)
  let pull = session.pull(viewer)
  check_pull(pull, sha)
  let problems = drafts.filter_map(draft => position_problem(files, draft))
  if !problems.is_empty() {
    raise Refused(problems.join("; "))
  }
  let owner = owner.unwrap_or("")
  let new_drafts = drafts_to_save(pull, owner, drafts)
  let new_replies = replies_to_save(pull, threads, owner, replies)
  let new_edits = edits_to_make(pull, edits)
  check_add_edit_conflicts(drafts, replies, threads, owner, new_edits)
  // The pending-review snapshot reads at most 100 comments, so keep the result readable after all additions.
  if comments_of(pull).length() + new_drafts.length() + new_replies.length() >
    100 {
    raise Refused("the pending review would have more than 100 comments")
  }
  let confirmed = (pull : Pull, threads : Map[String, Array[String]]) => {
    let saved = new_drafts.filter(draft => {
      comments_of(pull).iter().any(comment => is_saved(comment, owner, draft))
    })
    let edited = new_edits.filter(item => {
      find_comment(pull, item.0.id).map(comment => comment.text) ==
      Some(item.0.body)
    })
    let replied = new_replies.filter(reply => {
      reply_saved(pull, threads, owner, reply)
    })
    saved.length() + replied.length() + edited.length()
  }
  let total = new_drafts.length() + new_replies.length() + new_edits.length()
  let settle = async fn(message : String) -> Report raise Failure {
    let after = session.pull(viewer) catch {
      _ =>
        raise Unverified(
          "\{message}; the review could not be read back, so what was saved is unknown. Read it before trying again",
        )
    }
    let after_threads = session.threads(replies, after.id) catch {
      _ =>
        raise Unverified(
          "\{message}; the threads could not be read back, so what was saved is unknown. Read them before trying again",
        )
    }
    {
      text: "failed: \{message}\n\{confirmed(after, after_threads)} of \{total} changes are on the server. Running the same command again does the rest without duplicating the others.\n",
      code: 1,
    }
  }
  if !new_drafts.is_empty() || !new_replies.is_empty() {
    let review_id = match pull.review {
      Some(review) => review.id
      None =>
        start_review(session, pull, sha) catch {
          Api(message) => return settle(message)
          failure => raise failure
        }
    }
    for draft in new_drafts {
      save_draft(session, review_id, draft, owner) catch {
        Api(message) => return settle(message)
        failure => raise failure
      }
    }
    for reply in new_replies {
      save_reply(session, review_id, reply, owner) catch {
        Api(message) => return settle(message)
        failure => raise failure
      }
    }
  }
  for item in new_edits {
    let body = edited_body(item.0, item.1)
    let _ = (session.send)(EditComment(item.0.id, body)) catch {
      Api(message) => return settle(message)
      failure => raise failure
    }
  }
  let after = session.pull(viewer) catch {
    _ =>
      raise Unverified(
        "the changes were sent but the review could not be read back; read it again",
      )
  }
  let after_threads = session.threads(replies, after.id) catch {
    _ =>
      raise Unverified(
        "the changes were sent but the threads could not be read back; read them again",
      )
  }
  if confirmed(after, after_threads) != total {
    raise Unverified("the changes are not found in the pending review")
  }
  let head = "saved \{new_drafts.length()} new, \{drafts.length() - new_drafts.length()} already saved, edited \{new_edits.length()}, replied \{new_replies.length()} new, \{replies.length() - new_replies.length()} already saved"
  { text: head + "\n" + render(session, viewer, after), code: 0, }
}
