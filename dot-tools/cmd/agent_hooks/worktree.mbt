// Claude Code's PostToolUse hook for `git worktree add`: a checkout lacks the main worktree's git-ignored agent
// files, so the new worktree gets symlinks to them. Any failure skips the link, since the hook only helps.

///|
let worktree_candidates : Array[String] = [
  "exclude", ".docs", ".claude", "CLAUDE.md", "AGENTS.md",
]

///|
/// Links the ignored candidates into the worktree a `git worktree add` just made, and returns what it linked.
async fn worktree_post_add(event : Json) -> Array[String] {
  guard event
    is {
      "tool_name": "Bash",
      "tool_input": { "command": String(command), .. },
      ..
    } &&
    worktree_add_path(
      command,
      event_cwd(event),
      home=@env.get_env_var("HOME").unwrap_or(""),
    )
    is Some((dir, path)) else {
    return []
  }
  let response = match event {
    { "tool_response": String(text), .. } => text
    { "tool_response": value, .. } => value.stringify()
    _ => ""
  }
  // Git prints this only when it created the worktree, so a failed add links nothing.
  guard response.contains("Preparing worktree") else { return [] }
  let list = @git_trust.run_git(dir, ["worktree", "list", "--porcelain"]) catch {
    _ => return []
  }
  guard list.status == 0 else { return [] }
  let paths = list.stdout
    .split("\n")
    .filter_map(line => {
      line.strip_prefix("worktree ").map(path => path.to_owned())
    })
    .collect()
  // Git sorts linked worktrees by path, so the new one is found by the path the command named.
  // A path the shell still expands, as in `"$(pwd)/../x"`, falls back to the worktree Git just made.
  let added = if path.contains_char('$') || path.contains_char('`') {
    guard newest_worktree(dir) is Some(path) else { return [] }
    path
  } else {
    path
  }
  let added = @fs.realpath(added) catch { _ => return [] }
  guard paths is [main, .. linked] else { return [] }
  for listed in linked {
    let resolved = @fs.realpath(listed) catch { _ => continue }
    if resolved == added && resolved != (@fs.realpath(main) catch { _ => main }) {
      return link_ignored(main, listed)
    }
  }
  []
}

///|
/// How recently `git worktree add` must have made a worktree for it to count as the one a command just added.
let newest_worktree_window_ms : Int64 = 60000

///|
/// The worktree Git made last, by its `commondir` file, which only `git worktree add` writes;
/// one older than the window was there before the command, so none is picked.
async fn newest_worktree(dir : String) -> String? {
  let common = @git_trust.run_git(dir, ["rev-parse", "--git-common-dir"]) catch {
    _ => return None
  }
  guard common.status == 0 else { return None }
  let admin = @shell.join_path(
      dir,
      common.stdout.trim_end(chars="\n").to_owned(),
    ) +
    "/worktrees"
  let names = @fs.readdir(admin, include_hidden=true) catch { _ => return None }
  let mut newest : (Int64, String)? = None
  for name in names {
    let (seconds, nanoseconds) = @fs.mtime(admin + "/" + name + "/commondir") catch {
      _ => continue
    }
    let created = seconds * 1000 + (nanoseconds / 1000000).to_int64()
    if newest is Some((time, _)) && time >= created {
      continue
    }
    newest = Some((created, name))
  }
  guard newest is Some((created, name)) &&
    @async.now() - created <= newest_worktree_window_ms else {
    return None
  }
  // `gitdir` holds the path of the worktree's `.git` file, relative to its folder with `worktree.useRelativePaths`.
  let folder = admin + "/" + name
  let gitdir = @fs.read_file(folder + "/gitdir") catch { _ => return None }
  gitdir
  .text()
  .trim_end(chars="\n")
  .strip_suffix("/.git")
  .map(path => @shell.join_path(folder, path.to_owned()))
}

///|
/// Expands a leading `~`, `$HOME` or `$PWD` as the shell would, so the path can be found; other words stay as they are.
fn expand_path(word : String, cwd : String, home : String) -> String? {
  let variables = [
    ("~/", home + "/"),
    ("$HOME", home),
    ("${HOME}", home),
    ("$PWD", cwd),
    ("${PWD}", cwd),
  ]
  if word == "~" && home != "" {
    return Some(home)
  }
  for variable in variables {
    let (prefix, value) = variable
    if word.strip_prefix(prefix) is Some(rest) &&
      value != "" &&
      (prefix == "~/" || rest == "" || rest.has_prefix("/")) {
      return Some(value + rest.to_owned())
    }
  }
  None
}

///|
/// The directory Git runs in and the path a leading `git worktree add` creates, both joined to `cwd`.
fn worktree_add_path(
  command : String,
  cwd : String,
  home~ : String,
) -> (String, String)? {
  guard @git_command.segments(command) is [[first, ..] as segment, ..] &&
    @shell.basename(first) == "git" &&
    @git_command.subcommand(segment)
    is Some((dir, "worktree", ["add", .. args])) else {
    return None
  }
  let dir = match dir {
    Some(dir) => @shell.join_path(cwd, dir)
    None => cwd
  }
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    index += 1
    if arg == "--" {
      break
    } else if arg == "--reason" {
      index += 1
    } else if arg.has_prefix("--") {
      continue
    } else if arg.has_prefix("-") && arg.length() > 1 {
      // In a cluster like `-fb name`, `-b` and `-B` take the rest or the next word.
      match arg.find_by(char => char == 'b' || char == 'B') {
        Some(at) => if at == arg.length() - 1 { index += 1 }
        None => ()
      }
    } else {
      index -= 1
      break
    }
  }
  guard index < args.length() else { return None }
  let path = args[index]
  // The shell expands against its own directory, before `-C` moves Git.
  match expand_path(path, cwd, home) {
    Some(path) => Some((dir, path))
    None => Some((dir, @shell.join_path(dir, path)))
  }
}

///|
async fn link_ignored(main : String, newest : String) -> Array[String] {
  let present : Array[String] = []
  for item in worktree_candidates {
    let exists = @fs.exists(main + "/" + item) catch { _ => false }
    if exists {
      present.push(item)
    }
  }
  let ignored = ignored_paths(main, present)
  let linked = []
  for item in present {
    let source = main + "/" + item
    let target = newest + "/" + item
    if ignored.contains(item) {
      // A tracked copy in the new worktree would hide the main worktree's file.
      if is_directory(target, follow=false) {
        @fs.rmdir(target, recursive=true) catch {
          _ => continue
        }
      }
      if replace_link(source, target) {
        linked.push(item)
      }
    } else if !is_directory(source, follow=true) {
      continue
    } else if !is_directory(target, follow=true) {
      if replace_link(source, target) {
        linked.push(item + "/")
      }
    } else {
      // Both have the folder, so only the ignored files inside it are linked.
      let names = @fs.readdir(source, include_hidden=false, sort=true) catch {
        _ => continue
      }
      let inner = ignored_paths(main, names.map(name => item + "/" + name))
      for name in names {
        let path = item + "/" + name
        if inner.contains(path) &&
          replace_link(source + "/" + name, target + "/" + name) {
          linked.push(path)
        }
      }
    }
  }
  linked
}

///|
/// One `git check-ignore` for all paths, where the shell hook ran one per path.
async fn ignored_paths(dir : String, paths : Array[String]) -> Array[String] {
  guard !paths.is_empty() else { return [] }
  // `-z` needs `--stdin`, so the paths are printed one per line, unquoted.
  let result = @git_trust.run_git(
    dir,
    ["-c", "core.quotepath=off", "check-ignore", "--", ..paths],
  ) catch {
    _ => return []
  }
  guard result.status == 0 else { return [] }
  result.stdout
  .split("\n")
  .filter(path => path != "")
  .map(path => path.to_owned())
  .collect()
}

///|
async fn is_directory(path : String, follow~ : Bool) -> Bool {
  (@fs.kind(path, follow_symlink=follow) catch { _ => Unknown }) == Directory
}

///|
/// Points `target` at `source` like `ln -sfn`, except that a real folder at `target` is left alone.
async fn replace_link(source : String, target : String) -> Bool {
  let kind = @fs.kind(target, follow_symlink=false) catch { _ => Unknown }
  if kind == Directory {
    return false
  }
  if kind != Unknown {
    @fs.remove(target) catch {
      _ => return false
    }
  }
  @fs.symlink(target=source, target) catch {
    _ => return false
  }
  true
}
