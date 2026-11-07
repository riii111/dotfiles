///|
/// Problems when the title or the prose of the body is not in `language`, which is `ja` or `en`.
pub fn check_language(
  language : String,
  title : String?,
  body : String?,
) -> Array[String] {
  let prose = prose_lines(body.unwrap_or(""))
    .iter()
    .filter(line => {
      let stripped = @text.strip(line)
      stripped != "" && !is_reference_line(stripped)
    })
    .collect()
  let mismatched = if language == "ja" {
    (title is Some(title) && !has_japanese(title)) ||
    (!prose.is_empty() && !prose.iter().any(has_japanese))
  } else {
    [title.unwrap_or(""), ..prose].iter().any(has_japanese)
  }
  if mismatched {
    let name = if language == "ja" { "日本語" } else { "英語" }
    ["このリポジトリのPRは\{name}で書く"]
  } else {
    []
  }
}

///|
/// The lines outside code fences, without inline code and link targets.
fn prose_lines(body : String) -> Array[String] {
  let lines = []
  let mut in_fence = false
  for line in @text.split_lines(body) {
    if skip_indent(line).has_prefix("```") {
      in_fence = !in_fence
    } else if !in_fence {
      lines.push(remove_link_targets(remove_code_spans(line)))
    }
  }
  lines
}

///|
fn skip_indent(line : String) -> String {
  match line.find_by(char => !@shell.is_python_whitespace(char)) {
    Some(index) => line.view(start_offset=index).to_owned()
    None => ""
  }
}

///|
/// Removes `` `[^`\n]*` `` spans.
fn remove_code_spans(line : String) -> String {
  let result = StringBuilder()
  let mut index = 0
  while index < line.length() {
    if line.code_unit_at(index) == '`' &&
      line.view(start_offset=index + 1).find("`") is Some(offset) {
      index += offset + 2
      continue
    }
    result.write_char(line.get_char(index).unwrap())
    index += line.get_char(index).unwrap().utf16_len()
  }
  result.to_string()
}

///|
/// Replaces `\]\([^)\s]*\)` with `]`.
fn remove_link_targets(line : String) -> String {
  let result = StringBuilder()
  let mut index = 0
  while index < line.length() {
    let char = line.get_char(index).unwrap()
    if char == ']' && link_target_end(line, index + 1) is Some(end) {
      result.write_char(']')
      index = end
      continue
    }
    result.write_char(char)
    index += char.utf16_len()
  }
  result.to_string()
}

///|
fn link_target_end(line : String, start : Int32) -> Int32? {
  guard line.view(start_offset=start).has_prefix("(") else { return None }
  let mut index = start + 1
  while line.get_char(index) is Some(char) {
    if char == ')' {
      return Some(index + 1)
    }
    if @shell.is_python_whitespace(char) {
      return None
    }
    index += char.utf16_len()
  }
  None
}

///|
fn is_japanese(char : Char) -> Bool {
  let code = char.to_int()
  (code >= 0x3040 && code <= 0x30FF) || (code >= 0x3400 && code <= 0x9FFF)
}

///|
fn has_japanese(text : String) -> Bool {
  text.iter().any(is_japanese)
}

///|
fn is_ascii_word(char : Char) -> Bool {
  char.is_ascii_alphabetic() || char.is_ascii_digit()
}

///|
/// Mirrors `JA[ \t]+ASCII|ASCII[ \t]+JA`.
fn has_mixed_space(text : String) -> Bool {
  let chars = text.iter().collect()
  let mut index = 0
  while index < chars.length() {
    guard chars[index] == ' ' || chars[index] == '\t' else {
      index += 1
      continue
    }
    let start = index
    while index < chars.length() &&
          (chars[index] == ' ' || chars[index] == '\t') {
      index += 1
    }
    if start > 0 && index < chars.length() {
      let before = chars[start - 1]
      let after = chars[index]
      if (is_japanese(before) && is_ascii_word(after)) ||
        (is_ascii_word(before) && is_japanese(after)) {
        return true
      }
    }
  }
  false
}
