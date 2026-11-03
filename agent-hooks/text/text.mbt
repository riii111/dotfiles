// The hooks moved here from Python keep its Unicode-aware `\w`, `\d` and `str.splitlines()`, which the MoonBit regex lacks.
// A full Unicode table would take hundreds of ranges, so non-ASCII word characters are approximated by excluding the
// punctuation, symbol and mark blocks that appear in commands and Japanese or English PR text.

///|
/// Approximates Python's `\w`: letters, digits and `_`.
pub fn is_word_char(char : Char) -> Bool {
  if char.is_ascii() {
    return char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_'
  }
  if @shell.is_python_whitespace(char) {
    return false
  }
  match char.to_int() {
    0xAA | 0xB2 | 0xB3 | 0xB5 | 0xB9 | 0xBA | 0xBC..<=0xBE => true
    0x80..<=0xBF | 0xD7 | 0xF7 => false
    0x0300..<=0x036F => false
    0x2000..<=0x206F => false
    0x2460..<=0x24FF => true
    0x2190..<=0x2BFF => false
    0x3005..<=0x3007 | 0x3021..<=0x3029 | 0x3031..<=0x3035 | 0x3038..<=0x303C =>
      true
    0x3000..<=0x303F => false
    0x3099..<=0x309C | 0x30A0 | 0x30FB => false
    0xFE30..<=0xFE4F => false
    0xFF01..<=0xFF0F | 0xFF1A..<=0xFF20 | 0xFF3B..<=0xFF40 | 0xFF5B..<=0xFF65 =>
      false
    0xFFE0..<=0xFFEF => false
    0x1F000..<=0x1FAFF => false
    _ => true
  }
}

///|
/// Approximates Python's `\d` with the ASCII and full-width digits.
pub fn is_decimal(char : Char) -> Bool {
  char.is_ascii_digit() || (char >= '０' && char <= '９')
}

///|
/// Splits lines like Python's `str.splitlines()`, without the line endings.
pub fn split_lines(text : String) -> Array[String] {
  let lines = []
  let line = StringBuilder()
  let mut index = 0
  while index < text.length() {
    let char = text.get_char(index).unwrap()
    index += char.utf16_len()
    if !is_line_break(char) {
      line.write_char(char)
      continue
    }
    if char == '\r' && text.get_char(index) is Some('\n') {
      index += 1
    }
    lines.push(line.to_string())
    line.reset()
  }
  if !line.is_empty() {
    lines.push(line.to_string())
  }
  lines
}

///|
fn is_line_break(char : Char) -> Bool {
  match char.to_int() {
    0x0A..<=0x0D | 0x1C..<=0x1E | 0x85 | 0x2028 | 0x2029 => true
    _ => false
  }
}

///|
/// Removes leading and trailing whitespace like Python's `str.strip()`.
pub fn strip(text : StringView) -> String {
  let chars = text.iter().collect()
  let mut start = 0
  let mut end = chars.length()
  while start < end && @shell.is_python_whitespace(chars[start]) {
    start += 1
  }
  while end > start && @shell.is_python_whitespace(chars[end - 1]) {
    end -= 1
  }
  String::from_array(chars[start:end])
}

///|
/// Tells whether the word `word` occurs in `text` with word boundaries on both sides, like Python's `\bword\b`.
pub fn has_word(text : String, word : String, from~ : Int32 = 0) -> Bool {
  word_at(text, word, from~) is Some(_)
}

///|
/// Returns the index of the first `word` at or after `from` that has word boundaries on both sides.
pub fn word_at(text : String, word : String, from~ : Int32 = 0) -> Int32? {
  let mut start = from
  while start <= text.length() - word.length() {
    guard text.view(start_offset=start).find(word) is Some(offset) else {
      return None
    }
    let index = start + offset
    if is_boundary(text, index) && is_boundary(text, index + word.length()) {
      return Some(index)
    }
    start = index + 1
  }
  None
}

///|
/// Tells whether a Python `\b` holds at `index`.
pub fn is_boundary(text : String, index : Int32) -> Bool {
  word_before(text, index) != word_after(text, index)
}

///|
fn word_before(text : String, index : Int32) -> Bool {
  index > 0 && char_before(text, index) is Some(char) && is_word_char(char)
}

///|
fn word_after(text : String, index : Int32) -> Bool {
  text.get_char(index) is Some(char) && is_word_char(char)
}

///|
/// The character that ends right before the UTF-16 offset `index`.
pub fn char_before(text : String, index : Int32) -> Char? {
  guard index > 0 else { return None }
  if index >= 2 &&
    text.get_char(index - 2) is Some(char) &&
    char.utf16_len() == 2 {
    return Some(char)
  }
  text.get_char(index - 1)
}
