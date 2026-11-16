///|
priv suberror Failure {
  Refused(String)
  Api(String)
  Unverified(String)
  NotPending(String)
}

///|
fn Json::field(self : Json, key : String) -> Json {
  match self {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn Json::text(self : Json) -> String? {
  match self {
    String(text) => Some(text)
    _ => None
  }
}

///|
fn Json::int(self : Json) -> Int32? {
  match self {
    Number(number, ..) => Some(number.to_int())
    _ => None
  }
}

///|
fn Json::items(self : Json) -> Array[Json] {
  match self {
    Array(items) => items
    _ => []
  }
}

///|
fn Json::flag(self : Json) -> Bool {
  self is True
}

///|
fn required_text(json : Json, key : String) -> String raise Failure {
  match json.field(key).text() {
    Some(text) => text
    None => raise Unverified("GitHub response lacks \{key}")
  }
}

///|
let marker_prefix : String = "<!-- pending-review owner="

///|
let marker_suffix : String = " -->"

///|
fn with_marker(body : String, owner : String) -> String {
  "\{body}\n\n\{marker_prefix}\{owner}\{marker_suffix}"
}

///|
fn split_marker(raw : String) -> (String, String?) {
  guard raw.has_suffix(marker_suffix) &&
    raw.rev_find(marker_prefix) is Some(start) else {
    return (raw.trim().to_owned(), None)
  }
  let owner_start = start + marker_prefix.length()
  let owner_end = raw.length() - marker_suffix.length()
  guard owner_start <= owner_end else { return (raw.trim().to_owned(), None) }
  let owner = raw[owner_start:owner_end].to_owned()
  (raw[:start].trim().to_owned(), Some(owner))
}

///|
priv struct Comment {
  id : String
  path : String
  line : Int32
  state : String
  subject : String
  text : String
  owner : String?
}

///|
priv struct Review {
  id : String
  url : String
  commit : String
  comments : Array[Comment]
}

///|
priv struct Pull {
  id : String
  url : String
  state : String
  head : String
  review : Review?
}

///|
fn parse_comment(json : Json) -> Comment raise Failure {
  let (text, owner) = split_marker(required_text(json, "body"))
  let line = match json.field("line").int() {
    Some(line) => line
    None => json.field("originalLine").int().unwrap_or(0)
  }
  {
    id: required_text(json, "id"),
    path: required_text(json, "path"),
    line,
    state: required_text(json, "state"),
    subject: required_text(json, "subjectType"),
    text,
    owner,
  }
}

///|
fn parse_pull(json : Json, viewer : String) -> Pull raise Failure {
  let pull = json.field("data").field("repository").field("pullRequest")
  guard pull is Object(_) else {
    raise Refused("the pull request was not found or is not readable")
  }
  let reviews = pull.field("reviews")
  if reviews.field("pageInfo").field("hasNextPage").flag() {
    raise Refused("more pending reviews than expected; the state is unclear")
  }
  let mine = reviews
    .field("nodes")
    .items()
    .filter(review => {
      review.field("author").field("login").text() == Some(viewer)
    })
  let review = match mine {
    [] => None
    [review] => Some(parse_review(review))
    _ =>
      raise Refused(
        "several pending reviews of \{viewer}; the state is unclear",
      )
  }
  {
    id: required_text(pull, "id"),
    url: required_text(pull, "url"),
    state: required_text(pull, "state"),
    head: required_text(pull, "headRefOid"),
    review,
  }
}

///|
fn parse_review(json : Json) -> Review raise Failure {
  let state = required_text(json, "state")
  if state != "PENDING" {
    raise Refused("the review is \{state}, not pending, so it is left alone")
  }
  let comments = json.field("comments")
  if comments.field("pageInfo").field("hasNextPage").flag() {
    raise Refused("the pending review has too many comments to read in full")
  }
  {
    id: required_text(json, "id"),
    url: required_text(json, "url"),
    commit: required_text(json.field("commit"), "oid"),
    comments: comments.field("nodes").items().map(parse_comment),
  }
}
