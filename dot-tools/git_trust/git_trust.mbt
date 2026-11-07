// A trusted repository is a ghq checkout at ~/ghq/github.com/OWNER/REPO whose every fetch and push URL for origin is that GitHub repository.
// Codex wrappers that run outside the sandbox use it to decide which checkout they may read from or push to.

///|
/// The result of a finished Git command.
pub(all) struct GitOutput {
  status : Int32
  stdout : String
  stderr : String
}

///|
/// The current environment without `GIT_*` variables, which could otherwise redirect the repository or its configuration.
pub fn git_environment() -> Map[String, String] {
  let environment = Map([])
  for name, value in @env.get_env_vars() {
    if !name.has_prefix("GIT_") {
      environment[name] = value
    }
  }
  environment
}

///|
/// Runs Git in `cwd` without the caller's `GIT_*` variables.
/// Raises when Git cannot start or prints output that is not UTF-8.
pub async fn run_git(cwd : String, args : Array[String]) -> GitOutput {
  let (status, stdout, stderr) = @process.collect_output(
    "git",
    args,
    extra_env=git_environment(),
    inherit_env=false,
    cwd~,
  )
  {
    status,
    stdout: stdout.text(),
    stderr: @utf8.decode_lossy(stderr.binary()),
  }
}

///|
/// Tells whether `ssh -G HOST` resolves to GitHub's SSH endpoint within two seconds.
pub async fn github_host(host : String) -> Bool {
  guard host != "" else { return false }
  // A fetch and a push URL usually name the same host, and ssh's configuration does not change within a hook run.
  if github_hosts.get(host) is Some(answer) {
    return answer
  }
  let answer = resolve_github_host(host)
  github_hosts[host] = answer
  answer
}

///|
let github_hosts : Map[String, Bool] = Map([])

///|
async fn resolve_github_host(host : String) -> Bool {
  let config = @async.with_timeout_opt(2000, () => {
    @process.collect_output(
      "ssh",
      ["-G", host],
      extra_env=git_environment(),
      inherit_env=false,
    )
  }) catch {
    _ => return false
  }
  guard config is Some((0, stdout, _)) else { return false }
  is_github_endpoint(stdout.text()) catch {
    _ => false
  }
}

///|
/// Returns the lowercased owner and repository of a GitHub remote URL.
pub async fn github_repository(url : String) -> (String, String)? {
  guard parse_remote(url) is Some(remote) else { return None }
  let on_github = match remote.host {
    Https(host) => host == "github.com"
    Ssh(host) => github_host(host)
  }
  if on_github {
    Some((remote.owner, remote.repo))
  } else {
    None
  }
}

///|
/// Returns the checkout root when `cwd` is in a ghq checkout at `~/ghq/github.com/OWNER/REPO`.
/// `home` defaults to `$HOME`.
pub async fn repository_root(cwd : String, home? : String) -> String? {
  guard checkout(cwd, home) is Some((root, _)) else { return None }
  Some(root)
}

///|
async fn checkout(cwd : String, home : String?) -> (String, (String, String))? {
  let result = run_git(cwd, [
    "rev-parse", "--path-format=absolute", "--git-common-dir",
  ]) catch {
    _ => return None
  }
  guard result.status == 0 else { return None }
  let common_dir = @fs.realpath(result.stdout.trim()) catch { _ => return None }
  guard common_dir.rev_split_once("/") is Some((root, ".git")) else {
    return None
  }
  let home = match home {
    Some(home) => home
    None => @env.get_env_var("HOME").unwrap_or("")
  }
  guard home != "" else { return None }
  let trusted_root = @fs.realpath(home + "/ghq/github.com") catch {
    _ => return None
  }
  guard relative_parts(root.to_owned(), trusted_root) is Some([owner, repo]) else {
    return None
  }
  Some((root.to_owned(), (owner, repo)))
}

///|
/// Splits `path` below `base`; both must be absolute and already resolved.
pub fn relative_parts(path : String, base : String) -> Array[String]? {
  let base = if base.has_suffix("/") { base } else { base + "/" }
  guard path.strip_prefix(base) is Some(relative) && relative != "" else {
    return None
  }
  let parts = relative.split("/").map(part => part.to_owned()).collect()
  guard parts.iter().all(part => part != "") else { return None }
  Some(parts)
}

///|
/// Returns the checkout root when it is a ghq checkout whose every origin fetch and push URL is the matching GitHub repository.
/// `home` defaults to `$HOME`. Remote names are always lowercased; `ignore_case` lowercases the checkout's too, as the
/// Codex command policy always did, while the Codex wrappers keep the case-sensitive match they had in Python.
pub async fn trusted_repository(
  cwd : String,
  home? : String,
  ignore_case~ : Bool = false,
) -> String? {
  guard checkout(cwd, home) is Some((root, (owner, repo))) else { return None }
  let expected = if ignore_case {
    (owner.to_lower(), repo.to_lower())
  } else {
    (owner, repo)
  }
  for push in [false, true] {
    let args = ["remote", "get-url"]
    if push {
      args.push("--push")
    }
    args.push_iter(["--all", "origin"].iter())
    let result = run_git(cwd, args) catch { _ => return None }
    guard result.status == 0 else { return None }
    let urls = result.stdout
      .split("\n")
      .filter(line => line != "")
      .map(line => line.to_owned())
      .collect()
    guard urls is [_, ..] else { return None }
    for url in urls {
      guard github_repository(url) is Some(found) && found == expected else {
        return None
      }
    }
  }
  Some(root)
}
