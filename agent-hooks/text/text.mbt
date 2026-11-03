// The hooks moved here from Python keep its Unicode-aware `\w`, `\d` and `str.splitlines()`, which the MoonBit regex lacks.

///|
/// Matches Python's `\w`: letters, digits and `_`.
pub fn is_word_char(char : Char) -> Bool {
  if char.is_ascii() {
    char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_'
  } else {
    in_ranges(word_ranges, char.to_int())
  }
}

///|
/// Matches Python's `\d`: the Unicode decimal digits.
pub fn is_decimal(char : Char) -> Bool {
  if char.is_ascii() {
    char.is_ascii_digit()
  } else {
    in_ranges(decimal_ranges, char.to_int())
  }
}

///|
/// Binary search over inclusive start and end pairs.
fn in_ranges(ranges : FixedArray[Int32], code : Int32) -> Bool {
  let mut low = 0
  let mut high = ranges.length() / 2
  while low < high {
    let middle = (low + high) / 2
    if code < ranges[middle * 2] {
      high = middle
    } else if code > ranges[middle * 2 + 1] {
      low = middle + 1
    } else {
      return true
    }
  }
  false
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
