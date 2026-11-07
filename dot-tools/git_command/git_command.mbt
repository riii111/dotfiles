///|
let separators : Array[String] = [";", "&&", "||", "|", "&", "|&", "(", ")"]

///|
/// Unbalanced quotes fall back to splitting on whitespace, so a malformed command is still checked.
/// Here-document body lines are split as commands too: a body may be run by `bash <<EOF` or `ssh host <<EOF`,
/// and telling those from `cat <<EOF` is guesswork; a false deny is the safe failure.
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

///|
/// Expands a leading `~`, `$HOME` or `$PWD` as the shell would, so the path can be found; other words stay as they are.
pub fn expand_path(word : String, cwd : String, home : String) -> String? {
  // An unset HOME or PWD leaves the word as it is, rather than rooting `~/x` at `/x`.
  let variables = [
    ("~", home),
    ("$HOME", home),
    ("${HOME}", home),
    ("$PWD", cwd),
    ("${PWD}", cwd),
  ]
  for variable in variables {
    let (prefix, value) = variable
    if word.strip_prefix(prefix) is Some(rest) &&
      value != "" &&
      (rest == "" || rest.has_prefix("/")) {
      return Some(value + rest.to_owned())
    }
  }
  None
}

///|
/// Each segment but a plain `cd DIR`, with the directory the shell runs it in; a `cd` moves it for the segments after.
pub fn segments_in(
  command : String,
  cwd : String,
  home~ : String,
) -> Array[(String, Array[String])] {
  let mut dir = cwd
  let found = []
  for segment in segments(command) {
    if segment is ["cd", target] {
      dir = expand_path(target, dir, home).unwrap_or(
        @shell.join_path(dir, target),
      )
      continue
    }
    found.push((dir, segment))
  }
  found
}
