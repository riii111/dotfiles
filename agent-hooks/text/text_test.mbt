///|
test "word characters follow Python's \\w for ASCII and Japanese text" {
  for
    char in ['a', 'Z', '0', '_', 'あ', 'ア', 'ー', '漢', '々', '０', 'é'] {
    assert_true(@text.is_word_char(char))
  }
  for
    char in [
      '-', '.', ' ', '、', '。', '「', '・', '（', '＃', '\u{3000}', '→',
    ] {
    assert_false(@text.is_word_char(char))
  }
}

///|
test "word boundaries hold next to non-word characters" {
  assert_true(@text.has_word("cd x && gh pr edit", "gh"))
  assert_true(@text.has_word("「gh」", "gh"))
  assert_false(@text.has_word("ghx pr", "gh"))
  assert_false(@text.has_word("日本gh pr", "gh"))
  assert_eq(@text.word_at("ghx gh", "gh"), Some(4))
}

///|
test "lines split like Python's str.splitlines" {
  assert_eq(@text.split_lines("a\r\nb\rc\n\u{2028}d\n"), [
    "a", "b", "c", "", "d",
  ])
  assert_eq(@text.split_lines(""), [])
  assert_eq(@text.strip("\u{3000} a b\t\n"), "a b")
}
