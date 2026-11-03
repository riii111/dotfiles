// Codex allows this command outside the sandbox, so it only overwrites the current branch of a trusted repository, leased on the OID the remote reports.

///|
extern "C" fn exit(code : Int32) = "exit"

///|
async fn main {
  guard @env.args().length() == 1 else {
    @stdio.stderr.write("usage: codex-force-with-lease\n")
    exit(2)
  }
  let cwd = match @env.current_dir() {
    Some(cwd) => @fs.realpath(cwd) catch { _ => "" }
    None => ""
  }
  let trusted = cwd != "" && @git_trust.trusted_repository(cwd) is Some(_)
  let outcome = force_with_lease(trusted~, args => @git_trust.run_git(cwd, args))
  match outcome {
    Pushed(stdout) => @stdio.stdout.write(stdout)
    Refused(message) => @stdio.stderr.write(message + "\n")
    PushFailed(_, stderr) => @stdio.stderr.write(stderr)
  }
  exit(outcome.exit_code())
}

///|
priv enum Outcome {
  Pushed(String)
  Refused(String)
  PushFailed(Int32, String)
}

///|
fn Outcome::exit_code(self : Outcome) -> Int32 {
  match self {
    Pushed(_) => 0
    Refused(_) => 1
    PushFailed(status, _) => status
  }
}

///|
let protected_branches : Array[String] = ["main", "master"]

///|
async fn force_with_lease(
  trusted~ : Bool,
  git : async (Array[String]) -> @git_trust.GitOutput,
) -> Outcome {
  guard trusted else {
    return Refused("current repository is not a trusted GitHub checkout")
  }
  let branch_result = git(["symbolic-ref", "--quiet", "--short", "HEAD"]) catch {
    _ => return Refused("force-with-lease requires a non-protected branch")
  }
  let branch = branch_result.stdout.trim().to_owned()
  if branch_result.status != 0 ||
    branch == "" ||
    protected_branches.contains(branch) {
    return Refused("force-with-lease requires a non-protected branch")
  }
  let format = git(["check-ref-format", "--branch", branch]) catch {
    _ => return Refused("current branch name is invalid")
  }
  guard format.status == 0 else {
    return Refused("current branch name is invalid")
  }

  let remote_ref = "refs/heads/" + branch
  let lease_result = git(["ls-remote", "--heads", "origin", remote_ref]) catch {
    _ => return Refused("could not read the remote branch OID")
  }
  guard lease_result.status == 0 else {
    return Refused("could not read the remote branch OID")
  }
  let matches = []
  for line in lease_result.stdout.split("\n") {
    let fields = line
      .split(" ")
      .flat_map(field => field.split("\t"))
      .filter(field => field != "")
      .collect()
    if fields is [oid, name] &&
      is_oid(oid, uppercase=true) &&
      name == remote_ref {
      matches.push(oid.to_owned().to_lower())
    }
  }
  guard matches is [oid] else {
    return Refused("remote branch does not exist; refusing to create it")
  }

  let local_result = git(["rev-parse", "--verify", remote_ref]) catch {
    _ => return Refused("could not resolve the local branch OID")
  }
  let local_oid = local_result.stdout.trim().to_owned().to_lower()
  guard local_result.status == 0 && is_oid(local_oid, uppercase=false) else {
    return Refused("could not resolve the local branch OID")
  }

  let push = git([
    "push",
    "origin",
    "--force-with-lease=\{remote_ref}:\{oid}",
    "\{local_oid}:\{remote_ref}",
  ]) catch {
    error => return PushFailed(1, "\{error}\n")
  }
  if push.status != 0 {
    PushFailed(push.status, push.stderr)
  } else {
    Pushed(push.stdout)
  }
}

///|
fn is_oid(text : StringView, uppercase~ : Bool) -> Bool {
  text.length() == 40 &&
  text
  .iter()
  .all(char => {
    char.is_ascii_digit() ||
    (char >= 'a' && char <= 'f') ||
    (uppercase && char >= 'A' && char <= 'F')
  })
}
