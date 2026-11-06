// Hooks that check git commands read the arguments of each simple command, since permission rules only match prefixes.

///|
let separators : Array[String] = [";", "&&", "||", "|", "&", "|&", "(", ")"]

///|
/// Unbalanced quotes fall back to splitting on whitespace, so a malformed command is still checked.
pub fn segments(command : String) -> Array[Array[String]] {
  let normalized = command.replace_all(old="\n", new=" ; ")
  let words = @shell.split_words(normalized, punctuation=";&|()", comments=true) catch {
    _ => @shell.split_on_whitespace(normalized)
  }
  let segments = [[]]
  for word in words {
    if separators.contains(word) {
      segments.push([])
    } else {
      segments.last().unwrap().push(word)
    }
  }
  segments.filter(segment => !segment.is_empty())
}

///|
let options_with_value : Array[String] = [
  "-C", "-c", "--git-dir", "--work-tree", "--namespace",
]

///|
pub fn subcommand(
  segment : Array[String],
) -> (String?, String, ArrayView[String])? {
  guard segment.search_by(word => word == "git" || word.has_suffix("/git"))
    is Some(git) else {
    None
  }
  let mut dir = None
  let mut index = git + 1
  while index < segment.length() && segment[index].has_prefix("-") {
    if segment[index] == "-C" && index + 1 < segment.length() {
      dir = Some(segment[index + 1])
    }
    index += if options_with_value.contains(segment[index]) { 2 } else { 1 }
  }
  guard index < segment.length() else { None }
  Some((dir, segment[index], segment[index + 1:]))
}
