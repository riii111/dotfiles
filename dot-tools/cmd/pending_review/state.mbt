///|
priv suberror Failure {
  Refused(String)
  Api(String)
  Unverified(String)
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
fn with_marker(body : String, owner : String, side : Side) -> String {
  "\{body}\n\n\{marker_prefix}\{owner} side=\{side.name()}\{marker_suffix}"
}

///|
fn split_marker(raw : String) -> (String, String?, String?) {
  let plain = (raw.trim().to_owned(), None, None)
  guard raw.has_suffix(marker_suffix) &&
    raw.rev_find(marker_prefix) is Some(start) else {
    return plain
  }
  let inner_start = start + marker_prefix.length()
  let inner_end = raw.length() - marker_suffix.length()
  guard inner_start <= inner_end else { return plain }
  guard raw[inner_start:inner_end].to_owned().split(" side=").collect()
    is [owner, side] &&
    (side.to_owned() == "LEFT" || side.to_owned() == "RIGHT") else {
    return plain
  }
  (raw[:start].trim().to_owned(), Some(owner.to_owned()), Some(side.to_owned()))
}

///|
priv struct Comment {
  path : String
  line : Int32
  text : String
  owner : String?
  side : String?
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
  let (text, owner, side) = split_marker(required_text(json, "body"))
  let line = match json.field("line").int() {
    Some(line) => line
    None => json.field("originalLine").int().unwrap_or(0)
  }
  { path: required_text(json, "path"), line, text, owner, side, }
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
