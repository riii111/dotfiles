// The review reads the changes the commit will record, so a command that also stages or commits unstaged files widens what it reads.

///|
priv struct Commit {
  dir : String
  includes_unstaged : Bool
}

///|
/// Finds the first `git commit` in a Bash command and the directory it runs in.
/// A `git add` earlier in the same command, `-a`, or a path argument makes the commit take unstaged changes of tracked files.
fn find_commit(command : String, cwd : String) -> Commit? {
  let mut dir = cwd
  let mut staged_here = false
  for segment in split_segments(command) {
    if segment is ["cd", target] {
      dir = join(dir, target)
      continue
    }
    guard git_subcommand(segment) is Some((git_dir, subcommand, args)) else {
      continue
    }
    let run_dir = match git_dir {
      Some(path) => join(dir, path)
      None => dir
    }
    if subcommand == "add" {
      staged_here = true
      continue
    }
    guard subcommand == "commit" else { continue }
    guard commit_options(args) is Some(widens) else { return None }
    return Some({ dir: run_dir, includes_unstaged: staged_here || widens, })
  }
  None
}

///|
let separators : Array[String] = [";", "&&", "||", "|", "&", "|&", "(", ")"]

///|
fn split_segments(command : String) -> Array[Array[String]] {
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
fn join(base : String, path : String) -> String {
  if path.has_prefix("/") {
    path
  } else {
    base + "/" + path
  }
}

///|
let git_options_with_value : Array[String] = [
  "-C", "-c", "--git-dir", "--work-tree", "--namespace",
]

///|
/// Returns the `-C` directory, the subcommand and its arguments.
fn git_subcommand(
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
    index += if git_options_with_value.contains(segment[index]) { 2 } else { 1 }
  }
  guard index < segment.length() else { None }
  Some((dir, segment[index], segment[index + 1:]))
}

///|
let commit_options_with_value : Array[String] = [
  "-m", "--message", "-F", "--file", "-C", "--reuse-message", "-c", "--reedit-message",
  "--fixup", "--squash", "--author", "--date", "-t", "--template", "--cleanup", "--trailer",
  "--pathspec-from-file",
]

///|
/// Short options whose value may follow in the same word, as in `-am "message"`.
let short_value_flags : String = "mFCct"

///|
/// Returns whether the commit takes unstaged changes, or `None` when it records nothing.
fn commit_options(args : ArrayView[String]) -> Bool? {
  let mut widens = false
  let mut skip_value = false
  let mut paths_only = false
  for arg in args {
    if skip_value {
      skip_value = false
      continue
    }
    if paths_only || !arg.has_prefix("-") {
      widens = true
      continue
    }
    match arg {
      "--" => paths_only = true
      "--dry-run" | "-h" | "--help" => return None
      "--all" | "--include" | "--only" => widens = true
      _ if commit_options_with_value.contains(arg) => skip_value = true
      _ if arg.has_prefix("--") => ()
      _ =>
        for char in arg.iter().drop(1) {
          if char == 'a' || char == 'i' || char == 'o' {
            widens = true
          }
          if short_value_flags.contains_char(char) {
            skip_value = arg.has_suffix(char.to_string())
            break
          }
        }
    }
  }
  Some(widens)
}
