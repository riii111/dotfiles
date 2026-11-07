///|
let separators : Array[String] = [";", "&&", "||", "|", "&", "|&", "(", ")"]

///|
/// Unbalanced quotes fall back to splitting on whitespace, so a malformed command is still checked.
/// Here-document bodies are dropped first, since their lines would otherwise read as commands.
pub fn segments(command : String) -> Array[Array[String]] {
  let normalized = @shell.strip_heredocs(command).replace_all(
    old="\n",
    new=" ; ",
  )
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
/// Global options that take their value as the next word; `--exec-path` takes one only after `=`.
let options_with_value : Array[String] = [
  "-C", "-c", "--attr-source", "--config-env", "--git-dir", "--namespace", "--super-prefix",
  "--work-tree",
]

///|
pub fn takes_value(option : String) -> Bool {
  options_with_value.contains(option)
}

///|
/// The index of the subcommand in the words after `git`, past its global options.
pub fn subcommand_index(args : ArrayView[String]) -> Int32 {
  global_options(args).0
}

///|
/// One walk over the global options gives the subcommand's index and the directory `-C` names.
/// Git resolves each `-C` against the ones before it, and leaves the directory as is for an empty one.
fn global_options(args : ArrayView[String]) -> (Int32, String?) {
  let mut dir = None
  let mut index = 0
  while index < args.length() && args[index].has_prefix("-") {
    if args[index] == "-C" && index + 1 < args.length() && args[index + 1] != "" {
      let path = args[index + 1]
      dir = Some(
        match dir {
          Some(base) => @shell.join_path(base, path)
          None => path
        },
      )
    }
    index += if takes_value(args[index]) { 2 } else { 1 }
  }
  (index, dir)
}

///|
pub fn subcommand(
  segment : Array[String],
) -> (String?, String, ArrayView[String])? {
  guard segment.search_by(word => word == "git" || word.has_suffix("/git"))
    is Some(git) else {
    None
  }
  let args = segment[git + 1:]
  let (index, dir) = global_options(args)
  guard index < args.length() else { None }
  Some((dir, args[index], args[index + 1:]))
}
