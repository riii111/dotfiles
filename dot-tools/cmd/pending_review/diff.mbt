///|
priv struct Hunks {
  left : Array[(Int32, Int32)]
  right : Array[(Int32, Int32)]
}

///|
fn Hunks::contains(self : Hunks, side : Side, line : Int32) -> Bool {
  let ranges = match side {
    Left => self.left
    Right => self.right
  }
  ranges.iter().any(range => line >= range.0 && line < range.0 + range.1)
}

///|
fn parse_number(text : String) -> Int32? {
  Some(@string.parse_int(text)) catch {
    _ => None
  }
}

///|
fn parse_range(text : String) -> (Int32, Int32)? {
  guard text.length() > 1 else { return None }
  match text[1:].to_owned().split(",").map(part => part.to_owned()).collect() {
    [start] => parse_number(start).map(start => (start, 1))
    [start, count] =>
      match (parse_number(start), parse_number(count)) {
        (Some(start), Some(count)) => Some((start, count))
        _ => None
      }
    _ => None
  }
}

///|
fn parse_patch(patch : String) -> Hunks {
  // A hunk header's ranges cover the context and changed lines of each side, so the body lines need no parsing.
  let hunks = { left: [], right: [], }
  for line in patch.split("\n") {
    guard line.has_prefix("@@ -") else { continue }
    let words = line.to_owned().split(" ").collect()
    guard words is [_, old, new, ..] else { continue }
    if parse_range(old.to_owned()) is Some(left) &&
      parse_range(new.to_owned()) is Some(right) {
      hunks.left.push(left)
      hunks.right.push(right)
    }
  }
  hunks
}

///|
fn parse_files(entries : Array[Json]) -> Map[String, Hunks?] raise Failure {
  let files = Map([])
  for entry in entries {
    let path = required_text(entry, "filename")
    files[path] = entry.field("patch").text().map(parse_patch)
  }
  files
}

///|
fn position_problem(files : Map[String, Hunks?], draft : Draft) -> String? {
  match files.get(draft.path) {
    None => Some("\{draft.path} is not changed by the pull request")
    Some(None) =>
      Some(
        "GitHub returned no patch for \{draft.path}, so its lines cannot be checked",
      )
    Some(Some(hunks)) =>
      if hunks.contains(draft.side, draft.line) {
        None
      } else {
        Some(
          "\{draft.path}:\{draft.line} is not on the \{draft.side.name()} side of any hunk",
        )
      }
  }
}
