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
fn unknown_keys(json : Json, allowed : Array[String]) -> String? {
  guard json is Object(fields) else { return None }
  fields.keys().find_first(key => !allowed.contains(key))
}

///|
fn entries(json : Json, what : String) -> Array[Json] raise Failure {
  if unknown_keys(json, ["comments"]) is Some(key) {
    raise Refused("unknown input key \{key}")
  }
  guard json.field("comments") is Array(items) else {
    raise Refused("the input needs a \"comments\" array of \{what}")
  }
  if items.is_empty() || items.length() > max_comments {
    raise Refused("the input needs 1 to \{max_comments} comments")
  }
  items
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
fn parse_drafts(json : Json) -> Array[Draft] raise Failure {
  let drafts : Array[Draft] = []
  for entry in entries(json, "{path, line, side, body}") {
    if unknown_keys(entry, ["path", "line", "side", "body"]) is Some(key) {
      raise Refused("unknown comment key \{key}")
    }
    let path = match entry.field("path").text() {
      Some(path) if !path.is_empty() && !path.contains("\n") => path
      _ => raise Refused("every comment needs a one-line path")
    }
    let line = match entry.field("line") {
      Number(number, ..) if number == number.to_int().to_double() &&
        number >= 1.0 => number.to_int()
      _ => raise Refused("every comment needs a line number of 1 or more")
    }
    let side = match entry.field("side") {
      Null => Right
      String("RIGHT") => Right
      String("LEFT") => Left
      _ => raise Refused("side is LEFT or RIGHT")
    }
    let draft = { path, line, side, body: comment_body(entry), }
    if drafts
      .iter()
      .any(other => same_position(other, draft) && other.body == draft.body) {
      raise Refused("the same comment appears twice for \{path}:\{line}")
    }
    drafts.push(draft)
  }
  drafts
}

///|
fn same_position(a : Draft, b : Draft) -> Bool {
  a.path == b.path && a.line == b.line && a.side.name() == b.side.name()
}

///|
fn parse_edits(json : Json) -> Array[Edit] raise Failure {
  let edits : Array[Edit] = []
  for entry in entries(json, "{id, body}") {
    if unknown_keys(entry, ["id", "body"]) is Some(key) {
      raise Refused("unknown comment key \{key}")
    }
    let id = match entry.field("id").text() {
      Some(id) if !id.is_empty() => id
      _ => raise Refused("every edit needs a comment id")
    }
    if edits.iter().any(other => other.id == id) {
      raise Refused("the comment \{id} appears twice")
    }
    edits.push({ id, body: comment_body(entry), })
  }
  edits
}
