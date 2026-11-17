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
    // Handwritten comments keep the user's own style, so only comments saved by this command need a level.
    if comment.owner is Some(_) {
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
  let { sha, owner, drafts, edits, .. } = request
  let viewer = session.viewer()
  check_pull(session.pull(viewer), sha)
  let files = if drafts.is_empty() { Map([]) } else { session.diff() }
  let pull = session.pull(viewer)
  check_pull(pull, sha)
  let problems = drafts.filter_map(draft => position_problem(files, draft))
  if !problems.is_empty() {
    raise Refused(problems.join("; "))
  }
  let owner = owner.unwrap_or("")
  let new_drafts = drafts_to_save(pull, owner, drafts)
  let new_edits = edits_to_make(pull, edits)
  let confirmed = (pull : Pull) => {
    let saved = new_drafts.filter(draft => {
      comments_of(pull).iter().any(comment => is_saved(comment, owner, draft))
    })
    let edited = new_edits.filter(item => {
      find_comment(pull, item.0.id).map(comment => comment.text) ==
      Some(item.0.body)
    })
    saved.length() + edited.length()
  }
  let total = new_drafts.length() + new_edits.length()
  let settle = async fn(message : String) -> Report raise Failure {
    let after = session.pull(viewer) catch {
      _ =>
        raise Unverified(
          "\{message}; the review could not be read back, so what was saved is unknown. Read it before trying again",
        )
    }
    {
      text: "failed: \{message}\n\{confirmed(after)} of \{total} changes are on the server. Running the same command again does the rest without duplicating the others.\n",
      code: 1,
    }
  }
  if !new_drafts.is_empty() {
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
  if confirmed(after) != total {
    raise Unverified("the changes are not found in the pending review")
  }
  let head = "saved \{new_drafts.length()} new, \{drafts.length() - new_drafts.length()} already saved, edited \{new_edits.length()}"
  { text: head + "\n" + render(session, viewer, after), code: 0, }
}
