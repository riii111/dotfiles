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
fn describe(comment : Comment, owner : String?) -> String {
  let label = match comment.owner {
    Some(name) if Some(name) == owner => "yours"
    Some(name) => "owner \{name}"
    None => "manual"
  }
  "  \{comment.id}  \{comment.path}:\{comment.line}  [\{label}]  \{preview(comment.text)}"
}

///|
fn render(
  session : Session,
  viewer : String,
  pull : Pull,
  owner : String?,
) -> String {
  let target = session.target
  let lines = [
    "viewer: \{viewer}",
    "pull request: \{target.owner}/\{target.name}#\{target.number} \{pull.state} head \{short(pull.head)} \{pull.url}",
  ]
  match pull.review {
    None => lines.push("pending review: none")
    Some(review) => {
      let comments = review.comments
      let yours = comments
        .filter(comment => comment.owner is Some(_) && comment.owner == owner)
        .length()
      lines.push("pending review: PENDING \{review.url}")
      lines.push(
        "comments: \{comments.length()} in total, \{yours} saved by this owner",
      )
      for comment in comments {
        lines.push(describe(comment, owner))
      }
    }
  }
  lines.push("This command cannot submit the review; submit it on GitHub.")
  lines.join("\n") + "\n"
}

///|
async fn run_status(session : Session, owner : String?) -> Report raise Failure {
  let viewer = session.viewer()
  let pull = session.pull(viewer)
  { text: render(session, viewer, pull, owner), code: 0, }
}

///|
fn not_pending(what : String) -> Failure {
  NotPending(
    "\{what}; the review may have been submitted. Check the pull request on GitHub now",
  )
}

///|
async fn settle(
  session : Session,
  viewer : String,
  message : String,
  saved : (Pull) -> (Int32, Int32),
  target : Ref[String?],
) -> Report raise Failure {
  let pull = session.pull(viewer) catch {
    _ =>
      raise Unverified(
        "\{message}; the review could not be read back, so what was saved is unknown. Run status before trying again",
      )
  }
  if target.val is Some(id) && pull.review.map(review => review.id) != Some(id) {
    raise NotPending(
      "\{message}; the pending review is gone or replaced, so the comments saved before may have been published. Check the pull request on GitHub now and do not run this again",
    )
  }
  let (done, total) = saved(pull)
  {
    text: "failed: \{message}\n\{done} of \{total} comments are on the server. Running the same command again saves the rest without duplicating the others.\n",
    code: 1,
  }
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
    raise not_pending("GitHub did not report the new review as pending")
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
  let json = (session.send)(
    AddThread(review_id, draft, with_marker(draft.body, owner, draft.side)),
  )
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
    raise not_pending("GitHub did not report a saved comment as pending")
  }
}

///|
async fn run_add(
  session : Session,
  owner : String,
  sha : String,
  drafts : Array[Draft],
) -> Report raise Failure {
  let viewer = session.viewer()
  check_pull(session.pull(viewer), sha)
  let files = session.diff()
  let pull = session.pull(viewer)
  check_pull(pull, sha)
  let problems = drafts.filter_map(draft => position_problem(files, draft))
  if !problems.is_empty() {
    raise Refused(problems.join("; "))
  }
  let existing = comments_of(pull)
  let todo = drafts.filter(draft => {
    !existing.iter().any(comment => is_saved(comment, owner, draft))
  })
  let skipped = drafts.length() - todo.length()
  let target = Ref(pull.review.map(review => review.id))
  let count = (pull : Pull) => {
    let comments = comments_of(pull)
    let done = todo
      .filter(draft => comments.iter().any(c => is_saved(c, owner, draft)))
      .length()
    (done, todo.length())
  }
  if !todo.is_empty() {
    if target.val is None {
      target.val = Some(
        start_review(session, pull, sha) catch {
          Api(message) => return settle(session, viewer, message, count, target)
          failure => raise failure
        },
      )
    }
    for draft in todo {
      save_draft(session, target.val.unwrap(), draft, owner) catch {
        Api(message) => return settle(session, viewer, message, count, target)
        failure => raise failure
      }
    }
  }
  let after = session.pull(viewer) catch {
    _ =>
      raise Unverified(
        "the comments were saved but the review could not be read back; run status",
      )
  }
  let replaced = target.val is Some(id) &&
    after.review.map(review => review.id) != Some(id)
  if replaced ||
    (!todo.is_empty() && after.review is None) ||
    count(after).0 != todo.length() {
    raise not_pending("the saved comments are not found in the pending review")
  }
  let head = "saved \{todo.length()} new comments, \{skipped} already saved"
  { text: head + "\n" + render(session, viewer, after, Some(owner)), code: 0, }
}
