// Only whole-line comments count: a marker after code can sit inside a string, and telling it apart needs a parser for each language.

///|
priv enum CommentKind {
  Normal
  Doc
}

///|
priv struct Comment {
  path : String
  line : Int32
  kind : CommentKind
  text : String
}

///|
priv struct FileChanges {
  path : String
  mut added : Int32
  comments : Array[Comment]
}

///|
/// Reads the comments that `git diff -U0` adds, file by file, skipping files with no known comment syntax.
fn added_comments(diff : String) -> Array[FileChanges] {
  let files = []
  let mut current : FileChanges? = None
  let mut syntax : Syntax? = None
  let mut line = 0
  let mut in_block = false
  for raw in @text.split_lines(diff) {
    if raw.has_prefix("diff --git ") {
      current = None
      syntax = None
      continue
    }
    if raw.has_prefix("+++ ") {
      guard raw.strip_prefix("+++ b/") is Some(path) else { continue }
      let path = path.to_owned()
      syntax = syntax_for(path)
      if syntax is Some(_) {
        let changes = { path, added: 0, comments: [], }
        files.push(changes)
        current = Some(changes)
      }
      continue
    }
    if raw.has_prefix("@@ ") {
      line = hunk_start(raw)
      in_block = false
      continue
    }
    guard current is Some(changes) && syntax is Some(syntax) else { continue }
    if raw.has_prefix("+") {
      let content = raw.view(start_offset=1).to_owned()
      changes.added += 1
      match classify(syntax, content, in_block) {
        Some((kind, text, still_open)) => {
          in_block = still_open
          if text != "" {
            changes.comments.push({ path: changes.path, line, kind, text, })
          }
        }
        None => in_block = false
      }
      line += 1
    } else if raw.has_prefix(" ") {
      line += 1
    }
  }
  files.filter(changes => changes.added > 0)
}

///|
/// The new-file start line of a hunk header such as `@@ -3,0 +4,2 @@`.
fn hunk_start(header : String) -> Int32 {
  guard header.find(" +") is Some(index) else { return 0 }
  let mut start = 0
  for char in header.view(start_offset=index + 2) {
    guard char.is_ascii_digit() else { break }
    start = start * 10 + (char.to_int() - '0'.to_int())
  }
  start
}

///|
priv struct Syntax {
  line : Array[String]
  doc : Array[String]
  block : Bool
}

///|
let c_like : Syntax = { line: ["//"], doc: [], block: true, }

///|
let hash : Syntax = { line: ["#"], doc: [], block: false, }

///|
/// Generated files and documents have no entry, or are matched by name, so they are never reviewed.
fn syntax_for(path : String) -> Syntax? {
  let name = match path.rev_find("/") {
    Some(index) => path.view(start_offset=index + 1).to_owned()
    None => path
  }
  if name.contains(".generated.") || name.has_suffix(".lock") {
    return None
  }
  let name = name
    .strip_suffix(".tmpl")
    .map(view => view.to_owned())
    .unwrap_or(name)
  guard name.rev_find(".") is Some(dot) else { return None }
  match name.view(start_offset=dot + 1).to_owned() {
    "mbt" => Some({ line: ["//"], doc: ["///"], block: false, })
    "rs" => Some({ line: ["//"], doc: ["///", "//!"], block: true, })
    "go" | "c" | "h" | "java" | "kt" | "swift" | "scala" => Some(c_like)
    "ts" | "tsx" | "js" | "jsx" | "mjs" | "cjs" =>
      Some({ line: ["//"], doc: ["/**"], block: true, })
    "py" | "sh" | "bash" | "zsh" | "rb" | "toml" | "yml" | "yaml" => Some(hash)
    "nix" => Some({ line: ["#"], doc: [], block: true, })
    "lua" => Some({ line: ["--"], doc: ["---"], block: false, })
    _ => None
  }
}

///|
/// Returns the comment kind, its text without markers, and whether a block comment stays open after the line.
fn classify(
  syntax : Syntax,
  content : String,
  in_block : Bool,
) -> (CommentKind, String, Bool)? {
  let trimmed = @text.strip(content)
  if in_block {
    let closed = trimmed.contains("*/")
    let text = trimmed
      .replace_all(old="*/", new="")
      .trim_start(chars="*")
      .to_owned()
    return Some((Normal, @text.strip(text), !closed))
  }
  if trimmed.has_prefix("#!") {
    return None
  }
  for marker in syntax.doc {
    if trimmed.has_prefix(marker) && !trimmed.has_prefix("///|") {
      let open = marker == "/**" && !trimmed.contains("*/")
      return Some(
        (Doc, strip_markers(trimmed.view(start_offset=marker.length())), open),
      )
    }
  }
  if trimmed.has_prefix("///|") {
    return None
  }
  for marker in syntax.line {
    if trimmed.has_prefix(marker) {
      return Some(
        (
          Normal,
          strip_markers(trimmed.view(start_offset=marker.length())),
          false,
        ),
      )
    }
  }
  if syntax.block && trimmed.has_prefix("/*") {
    let open = !trimmed.contains("*/")
    return Some((Normal, strip_markers(trimmed.view(start_offset=2)), open))
  }
  None
}

///|
fn strip_markers(text : StringView) -> String {
  @text.strip(
    text.to_owned().replace_all(old="*/", new="").trim_start(chars="*/#-!"),
  )
}
