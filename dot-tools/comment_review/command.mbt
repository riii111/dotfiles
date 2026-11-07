///|
priv struct Commit {
  dir : String
  includes_unstaged : Bool
}

///|
fn find_commit(command : String, cwd : String, home~ : String) -> Commit? {
  let mut staged_here = false
  for item in @git_command.segments_in(command, cwd, home~) {
    let (dir, segment) = item
    guard @git_command.subcommand(segment) is Some((git_dir, subcommand, args)) else {
      continue
    }
    let run_dir = match git_dir {
      Some(path) => @shell.join_path(dir, path)
      None => dir
    }
    if subcommand == "add" {
      // Files this command stages are not in the index yet when the hook reads it, so the review reads unstaged changes too.
      staged_here = true
      continue
    }
    guard subcommand == "commit" else { continue }
    let includes_unstaged = match commit_scope(args) {
      NothingRecorded => return None
      Staged => staged_here
      WithUnstaged => true
    }
    return Some({ dir: run_dir, includes_unstaged, })
  }
  None
}

///|
let commit_options_with_value : Array[String] = [
  "-m", "--message", "-F", "--file", "-C", "--reuse-message", "-c", "--reedit-message",
  "--fixup", "--squash", "--author", "--date", "-t", "--template", "--cleanup", "--trailer",
  "--pathspec-from-file",
]

///|
priv enum CommitScope {
  Staged
  WithUnstaged
  NothingRecorded
}

///|
fn commit_scope(args : ArrayView[String]) -> CommitScope {
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
      "--dry-run" | "-h" | "--help" => return NothingRecorded
      "--all" | "--include" | "--only" => widens = true
      _ if commit_options_with_value.contains(arg) => skip_value = true
      _ if arg.has_prefix("--") => ()
      _ =>
        for char in arg.iter().drop(1) {
          if char == 'a' || char == 'i' || char == 'o' {
            widens = true
          }
          if commit_options_with_value.contains("-" + char.to_string()) {
            skip_value = arg.has_suffix(char.to_string())
            break
          }
        }
    }
  }
  if widens {
    WithUnstaged
  } else {
    Staged
  }
}
