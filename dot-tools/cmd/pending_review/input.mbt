///|
let max_comments : Int32 = 30

///|
let max_body_length : Int32 = 60000

///|
priv struct Edit {
  id : String
  body : String
}

///|
priv struct Request {
  target : Target
  sha : String
  owner : String
  drafts : Array[Draft]
  edits : Array[Edit]
}

///|
fn unknown_keys(json : Json, allowed : Array[String]) -> String? {
  guard json is Object(fields) else { return None }
  fields.keys().find_first(key => !allowed.contains(key))
}

///|
fn check_keys(json : Json, allowed : Array[String]) -> Unit raise Failure {
  if unknown_keys(json, allowed) is Some(key) {
    raise Refused("unknown input key \{key}")
  }
}

///|
fn list(json : Json, key : String) -> Array[Json] raise Failure {
  let items = match json.field(key) {
    Array(items) => items
    Null => []
    _ => raise Refused("\{key} is an array")
  }
  if items.length() > max_comments {
    raise Refused("\{key} takes at most \{max_comments} entries")
  }
  items
}

///|
fn[T] parse_all(
  items : Array[Json],
  parse : (Json) -> T raise Failure,
) -> Array[T] raise Failure {
  let parsed = []
  for item in items {
    parsed.push(parse(item))
  }
  parsed
}

///|
fn comment_body(entry : Json) -> String raise Failure {
  guard entry.field("body").text() is Some(body) else {
    raise Refused("every comment needs a text body")
  }
  let body = body.trim().to_owned()
  if body.is_empty() {
    raise Refused("a comment body is empty")
  }
  if body.length() > max_body_length {
    raise Refused("a comment body is longer than \{max_body_length} characters")
  }
  if body.contains(marker_prefix) {
    raise Refused("a comment body contains the marker of this command")
  }
  body
}

///|
fn parse_draft(entry : Json) -> Draft raise Failure {
  check_keys(entry, ["path", "line", "side", "body"])
  let path = match entry.field("path").text() {
    Some(path) if !path.is_empty() && !path.contains("\n") => path
    _ => raise Refused("every comment needs a one-line path")
  }
  let line = match entry.field("line") {
    Number(number, ..) if number == number.to_int().to_double() && number >= 1.0 =>
      number.to_int()
    _ => raise Refused("every comment needs a line number of 1 or more")
  }
  let side = match entry.field("side") {
    Null | String("RIGHT") => Right
    String("LEFT") => Left
    _ => raise Refused("side is LEFT or RIGHT")
  }
  { path, line, side, body: comment_body(entry), }
}

///|
fn parse_edit(entry : Json) -> Edit raise Failure {
  check_keys(entry, ["id", "body"])
  guard entry.field("id").text() is Some(id) && !id.is_empty() else {
    raise Refused("every edit needs a comment id")
  }
  { id, body: comment_body(entry), }
}

///|
fn is_name_char(char : Char) -> Bool {
  char.is_ascii_alphabetic() ||
  char.is_ascii_digit() ||
  char == '-' ||
  char == '_' ||
  char == '.'
}

///|
fn parse_target(json : Json) -> Target raise Failure {
  guard json.field("repo").text() is Some(repo) &&
    repo.split("/").collect() is [owner, name] &&
    !owner.is_empty() &&
    !name.is_empty() &&
    owner.iter().all(is_name_char) &&
    name.iter().all(is_name_char) else {
    raise Refused("repo is OWNER/REPO")
  }
  guard json.field("pr").int() is Some(number) && number > 0 else {
    raise Refused("pr is a positive number")
  }
  { owner: owner.to_owned(), name: name.to_owned(), number, }
}

///|
fn parse_request(json : Json, default_owner : String?) -> Request raise Failure {
  check_keys(json, ["repo", "pr", "sha", "owner", "add", "update"])
  let sha = match json.field("sha").text() {
    Some(sha) if sha.length() == 40 &&
      sha
      .iter()
      .all(char => char.is_ascii_digit() || (char >= 'a' && char <= 'f')) => sha
    _ => raise Refused("sha is the full 40-character commit ID in lowercase")
  }
  let owner = match json.field("owner").text() {
    Some(owner) => owner
    None => default_owner.unwrap_or("")
  }
  if owner.is_empty() || owner.length() > 64 || !owner.iter().all(is_name_char) {
    raise Refused(
      "owner is 1 to 64 letters, digits, '-', '_' or '.'; it defaults to CODEX_THREAD_ID",
    )
  }
  let drafts = parse_all(list(json, "add"), parse_draft)
  let edits = parse_all(list(json, "update"), parse_edit)
  { target: parse_target(json), sha, owner, drafts, edits, }
}
