///|
let sentence_closers : String = "」』）) "

///|
fn check_sentences(lines : Array[String]) -> Array[String] {
  let every = []
  let terminated = []
  for line in lines {
    if is_bullet(line) {
      continue
    }
    let parts = line.split("。").map(part => part.to_owned()).collect()
    for index, part in parts {
      if has_japanese(part) {
        every.push(part)
        if index < parts.length() - 1 {
          terminated.push(part)
        }
      }
    }
  }
  let problems = []
  if terminated.iter().any(ends_with_noun) {
    problems.push(
      "文末を述語で終える。名詞や数字で終わる文がある",
    )
  }
  if every
    .iter()
    .any(sentence => {
      has_reason_clause(sentence) && has_condition_clause(sentence)
    }) {
    problems.push("1文に理由と条件を重ねない。文を分ける")
  }
  problems
}

///|
/// Mirrors `[㐀-鿿゠-ヿA-Za-z0-9]$` after the closing brackets are removed.
fn ends_with_noun(sentence : String) -> Bool {
  let trimmed = sentence.trim_end(chars=sentence_closers)
  guard trimmed.iter().collect().last() is Some(char) else { return false }
  let code = char.to_int()
  (code >= 0x3400 && code <= 0x9FFF) ||
  (code >= 0x30A0 && code <= 0x30FF) ||
  is_ascii_word(char)
}

///|
fn has_reason_clause(sentence : String) -> Bool {
  ["ので、", "ため、", "から、"]
  .iter()
  .any(clause => sentence.contains(clause))
}

///|
fn has_condition_clause(sentence : String) -> Bool {
  ["れば、", "たら、", "なら、", "場合、"]
  .iter()
  .any(clause => sentence.contains(clause))
}
