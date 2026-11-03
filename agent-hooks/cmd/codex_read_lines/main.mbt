// Codex allows this command outside the sandbox, so it reads only files under the Codex skill folders or the current trusted repository.

///|
extern "C" fn exit(code : Int32) = "exit"

///|
let max_line : Int32 = 1_000_000

///|
async fn main {
  let code = run(@env.args().iter().drop(1).collect())
  exit(code)
}

///|
async fn run(args : Array[String]) -> Int32 {
  guard args is [start, end, path] else {
    @stdio.stderr.write("usage: codex-read-lines START END FILE\n")
    return 2
  }
  guard decimal(start) is Some(start) && decimal(end) is Some(end) else {
    @stdio.stderr.write("line numbers must be positive decimal integers\n")
    return 2
  }
  if start < 1 || end < start || end > max_line {
    @stdio.stderr.write("invalid line range\n")
    return 2
  }
  let cwd = current_dir()
  let home = @env.get_env_var("HOME").unwrap_or("")
  guard cwd is Some(cwd) && allowed_file(path, cwd~, home~) is Some(file) else {
    @stdio.stderr.write("file is outside an approved root\n")
    return 1
  }
  let lines = read_lines(file, start, end) catch {
    error => {
      @stdio.stderr.write("cannot read file: \{error}\n")
      return 1
    }
  }
  @stdio.stdout.write(lines)
  0
}

///|
/// Parses an ASCII decimal number, mapping anything above the line limit to `max_line + 1`.
fn decimal(text : String) -> Int32? {
  guard text != "" && text.iter().all(char => char.is_ascii_digit()) else {
    return None
  }
  let mut value = 0
  for char in text {
    value = value * 10 + (char.to_int() - '0'.to_int())
    if value > max_line {
      return Some(max_line + 1)
    }
  }
  Some(value)
}

///|
async fn current_dir() -> String? {
  guard @env.current_dir() is Some(cwd) else { return None }
  try @fs.realpath(cwd) catch {
    _ => None
  } noraise {
    resolved => Some(resolved)
  }
}

///|
/// Resolves `raw_path` against `cwd` and returns it when it is a regular file under an approved root.
async fn allowed_file(
  raw_path : String,
  cwd~ : String,
  home~ : String,
) -> String? {
  let candidate = if raw_path.has_prefix("/") {
    raw_path
  } else {
    cwd + "/" + raw_path
  }
  let resolved = @fs.realpath(candidate) catch { _ => return None }
  let kind = @fs.kind(resolved) catch { _ => return None }
  guard kind is Regular else { return None }
  for root in approved_roots(cwd, home) {
    if is_within(resolved, root) {
      return Some(resolved)
    }
  }
  None
}

///|
async fn approved_roots(cwd : String, home : String) -> Array[String] {
  let roots = []
  guard home != "" else { return roots }
  if resolve(home + "/.codex/skills") is Some(skills) {
    roots.push(skills)
  }
  roots.push_iter(plugin_skill_roots(home).iter())
  if @git_trust.trusted_repository(cwd, home~) is Some(repository) {
    roots.push(repository)
    if worktree_root(cwd) is Some(worktree) {
      roots.push(worktree)
    }
  }
  roots
}

///|
async fn resolve(path : String) -> String? {
  try @fs.realpath(path) catch {
    _ => None
  } noraise {
    resolved => Some(resolved)
  }
}

///|
/// Lists `~/.codex/plugins/cache/PROVIDER/PLUGIN/VERSION/skills`, skipping symlinked levels and skill folders that resolve outside the cache.
async fn plugin_skill_roots(home : String) -> Array[String] {
  let roots = []
  guard resolve(home + "/.codex/plugins/cache") is Some(cache) else {
    return roots
  }
  for provider in real_directories(cache) {
    for plugin in real_directories(provider) {
      for version in real_directories(plugin) {
        let skills = version + "/skills"
        guard is_directory(skills) && resolve(skills) is Some(resolved) else {
          continue
        }
        if is_within(resolved, cache) {
          roots.push(resolved)
        }
      }
    }
  }
  roots
}

///|
/// Lists the subdirectories of `parent` that are not symlinks.
async fn real_directories(parent : String) -> Array[String] {
  let names = @fs.readdir(parent, include_hidden=true) catch { _ => return [] }
  let directories = []
  for name in names {
    let path = parent + "/" + name
    let kind = @fs.kind(path, follow_symlink=false) catch { _ => continue }
    if kind is Directory {
      directories.push(path)
    }
  }
  directories
}

///|
async fn is_directory(path : String) -> Bool {
  try @fs.kind(path, follow_symlink=true) catch {
    _ => false
  } noraise {
    kind => kind is Directory
  }
}

///|
async fn worktree_root(cwd : String) -> String? {
  let result = @git_trust.run_git(cwd, ["rev-parse", "--show-toplevel"]) catch {
    _ => return None
  }
  guard result.status == 0 else { return None }
  resolve(result.stdout.trim().to_owned())
}

///|
fn is_within(path : String, root : String) -> Bool {
  path == root ||
  path.has_prefix(if root.has_suffix("/") { root } else { root + "/" })
}

///|
async fn read_lines(path : String, start : Int32, end : Int32) -> String {
  line_range(@utf8.decode(@fs.read_file(path).binary()), start, end)
}

///|
/// Returns lines `start..=end`.
/// Like Python's text mode, `\r\n` and a lone `\r` also end a line, and every line ending becomes `\n`.
fn line_range(text : String, start : Int32, end : Int32) -> String {
  let output = StringBuilder()
  let mut number = 1
  let mut line_start = 0
  let mut index = 0
  while index < text.length() && number <= end {
    let unit = text.code_unit_at(index)
    if unit != '\n' && unit != '\r' {
      index += 1
      continue
    }
    if number >= start {
      output.write_view(text.view(start_offset=line_start, end_offset=index))
      output.write_char('\n')
    }
    let crlf = unit == '\r' &&
      index + 1 < text.length() &&
      text.code_unit_at(index + 1) == '\n'
    index += if crlf { 2 } else { 1 }
    line_start = index
    number += 1
  }
  if number >= start && number <= end && line_start < text.length() {
    output.write_view(text.view(start_offset=line_start))
  }
  output.to_string()
}
