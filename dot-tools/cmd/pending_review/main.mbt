///|
extern "C" fn exit(code : Int32) = "exit"

///|
let usage : String =
  #|usage: pending-review status --repo OWNER/REPO --pr N [--owner ID]
  #|       pending-review add    --repo OWNER/REPO --pr N --sha SHA [--owner ID] < comments.json
  #|
  #|add reads {"comments": [{"path", "line", "side"?, "body"}]} from stdin.
  #|The owner defaults to $CODEX_THREAD_ID and tells apart the comments saved by each chat.
  #|

///|
async fn main {
  let args = @env.args().iter().drop(1).collect()
  let report = run(
    args,
    @env.get_env_var("CODEX_THREAD_ID"),
    () => @stdio.stdin.read_all().text(),
    gh_send,
  )
  if report.code == 0 {
    @stdio.stdout.write(report.text)
  } else {
    @stdio.stderr.write(report.text)
  }
  exit(report.code)
}

///|
priv enum Command {
  Status
  Add
}

///|
priv struct Options {
  command : Command
  repo : String
  pr : Int32
  sha : String?
  owner : String?
}

///|
priv suberror Usage {
  Usage(String)
}

///|
fn parse_options(args : Array[String]) -> Options? raise Usage {
  guard args is [name, .. rest] else { raise Usage("a subcommand is needed") }
  let command = match name {
    "-h" | "--help" => return None
    "status" => Status
    "add" => Add
    _ => raise Usage("unknown subcommand \{name}")
  }
  let mut repo = None
  let mut pr = None
  let mut sha = None
  let mut owner = None
  let mut index = 0
  while index < rest.length() {
    let arg = rest[index]
    index += 1
    match arg {
      "-h" | "--help" => return None
      "--repo" | "--pr" | "--sha" | "--owner" => {
        guard index < rest.length() else { raise Usage("\{arg} needs a value") }
        let value = rest[index]
        index += 1
        match arg {
          "--repo" => repo = Some(value)
          "--pr" => pr = Some(positive(value))
          "--sha" => sha = Some(value)
          _ => owner = Some(value)
        }
      }
      _ => raise Usage("unknown argument \{arg}")
    }
  }
  guard repo is Some(repo) else { raise Usage("--repo is needed") }
  guard pr is Some(pr) else { raise Usage("--pr is needed") }
  if command is Add && sha is None {
    raise Usage("--sha, the commit the review was made on, is needed")
  }
  Some({ command, repo, pr, sha, owner, })
}

///|
fn positive(value : String) -> Int32 raise Usage {
  let number = @string.parse_int(value) catch {
    _ => raise Usage("--pr needs a positive integer")
  }
  guard number > 0 else { raise Usage("--pr needs a positive integer") }
  number
}

///|
fn is_name_char(char : Char) -> Bool {
  char.is_ascii_alphabetic() ||
  char.is_ascii_digit() ||
  char == '-' ||
  char == '_' ||
  char == '.'
}

///|
fn parse_repo(repo : String, number : Int32) -> Target raise Usage {
  guard repo.split("/").collect() is [owner, name] &&
    !owner.is_empty() &&
    !name.is_empty() &&
    owner.iter().all(is_name_char) &&
    name.iter().all(is_name_char) else {
    raise Usage("--repo is OWNER/REPO")
  }
  { owner: owner.to_owned(), name: name.to_owned(), number, }
}

///|
fn is_commit(sha : String) -> Bool {
  sha.length() == 40 &&
  sha.iter().all(char => char.is_ascii_digit() || (char >= 'a' && char <= 'f'))
}

///|
fn is_owner(owner : String) -> Bool {
  !owner.is_empty() && owner.length() <= 64 && owner.iter().all(is_name_char)
}

///|
async fn run(
  args : Array[String],
  default_owner : String?,
  read_input : async () -> String,
  send : async (Operation) -> Json raise Failure,
) -> Report {
  let options = parse_options(args) catch {
    Usage(message) => return { text: "error: \{message}\n\{usage}", code: 2, }
  }
  guard options is Some(options) else { return { text: usage, code: 0, } }
  let target = parse_repo(options.repo, options.pr) catch {
    Usage(message) => return { text: "error: \{message}\n", code: 2, }
  }
  let owner = match options.owner {
    Some(_) as owner => owner
    None => default_owner
  }
  let session = { send, target, }
  let outcome = execute(session, options, owner, read_input) catch {
    Refused(message) => return { text: "refused: \{message}\n", code: 1, }
    Api(message) => return { text: "failed: \{message}\n", code: 1, }
    Unverified(message) => return { text: "unverified: \{message}\n", code: 3, }
    NotPending(message) =>
      return { text: "not pending: \{message}\n", code: 4, }
  }
  outcome
}

///|
async fn execute(
  session : Session,
  options : Options,
  owner : String?,
  read_input : async () -> String,
) -> Report raise Failure {
  if owner is Some(owner) && !is_owner(owner) {
    raise Refused("the owner is 1 to 64 letters, digits, '-', '_' or '.'")
  }
  match options.command {
    Status => run_status(session, owner)
    Add => {
      guard owner is Some(owner) else {
        raise Refused("--owner is needed when CODEX_THREAD_ID is not set")
      }
      guard options.sha is Some(sha) && is_commit(sha) else {
        raise Refused("--sha is the full 40-character commit ID in lowercase")
      }
      let input = @json.parse(read_input()) catch {
        _ => raise Refused("the input is not JSON")
      }
      run_add(session, owner, sha, parse_drafts(input))
    }
  }
}

///|
async fn gh_send(operation : Operation) -> Json raise Failure {
  let args = gh_args(operation)
  let outcome = @async.with_timeout_opt(30000, () => {
    @process.collect_output("gh", args)
  }) catch {
    error => raise Api("gh could not run: \{error}")
  }
  guard outcome is Some((status, stdout, stderr)) else {
    raise Api("gh did not answer within 30 seconds")
  }
  if status != 0 {
    let message = @utf8.decode_lossy(stderr.binary()).trim().to_owned()
    raise Api("gh exited with \{status}: \{preview(message)}")
  }
  let json = @json.parse(@utf8.decode_lossy(stdout.binary())) catch {
    _ => raise Api("gh returned text that is not JSON")
  }
  if json.field("errors") is Array([first, ..]) {
    raise Api(
      "GitHub reported an error: \{preview(first.field("message").text().unwrap_or(""))}",
    )
  }
  json
}
