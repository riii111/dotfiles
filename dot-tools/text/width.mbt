///|
/// The terminal columns `text` takes, without ANSI escape sequences.
pub fn visible_width(text : String) -> Int32 {
  let mut width = 0
  let mut escaped = false
  for char in text {
    if escaped {
      escaped = !char.is_ascii_alphabetic()
      continue
    }
    if char == '\u{1b}' {
      escaped = true
      continue
    }
    width += char_width(char)
  }
  width
}

///|
/// Two columns for emoji, CJK scripts and full-width forms; none for control characters and joiners.
fn char_width(char : Char) -> Int32 {
  let code = char.to_int()
  if code < 0x20 || code == 0xFE0F || code == 0x200D {
    return 0
  }
  if (code >= 0x1F300 && code <= 0x1FAFF) ||
    is_east_asian_script(code) ||
    (code >= 0xFF01 && code <= 0xFF60) ||
    (code >= 0xFFE0 && code <= 0xFFE6) {
    2
  } else {
    1
  }
}

///|
/// The Han, Hangul, Katakana and Hiragana script ranges of Go's `unicode` tables.
fn is_east_asian_script(code : Int32) -> Bool {
  match code {
    0x1100..<=0x11FF
    | 0x2E80..<=0x2E99
    | 0x2E9B..<=0x2EF3
    | 0x2F00..<=0x2FD5
    | 0x3005
    | 0x3007
    | 0x3021..<=0x3029
    | 0x302E..<=0x302F
    | 0x3038..<=0x303B
    | 0x3041..<=0x3096
    | 0x309D..<=0x309F
    | 0x30A1..<=0x30FA
    | 0x30FD..<=0x30FF
    | 0x3131..<=0x318E
    | 0x31F0..<=0x31FF
    | 0x3200..<=0x321E
    | 0x3260..<=0x327E
    | 0x32D0..<=0x32FE
    | 0x3300..<=0x3357
    | 0x3400..<=0x4DBF
    | 0x4E00..<=0x9FFF
    | 0xA960..<=0xA97C
    | 0xAC00..<=0xD7A3
    | 0xD7B0..<=0xD7C6
    | 0xD7CB..<=0xD7FB
    | 0xF900..<=0xFA6D
    | 0xFA70..<=0xFAD9
    | 0xFF66..<=0xFF6F
    | 0xFF71..<=0xFF9D
    | 0xFFA0..<=0xFFBE
    | 0xFFC2..<=0xFFC7
    | 0xFFCA..<=0xFFCF
    | 0xFFD2..<=0xFFD7
    | 0xFFDA..<=0xFFDC
    | 0x16FE2..<=0x16FE3
    | 0x16FF0..<=0x16FF1
    | 0x1AFF0..<=0x1B122
    | 0x1B132
    | 0x1B150..<=0x1B152
    | 0x1B155
    | 0x1B164..<=0x1B167
    | 0x1F200
    | 0x20000..<=0x2A6DF
    | 0x2A700..<=0x2EBE0
    | 0x2F800..<=0x2FA1D
    | 0x30000..<=0x323AF => true
    _ => false
  }
}
