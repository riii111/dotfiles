///|
extern "C" fn exit(code : Int32) = "exit"

///|
async fn main {
  let report = run(
    @stdio.stdin.read_all().text(),
    @env.get_env_var("CODEX_THREAD_ID"),
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
async fn run(
  input : String,
  default_owner : String?,
  send : async (Operation) -> Json raise Failure,
) -> Report {
  run_json(input, default_owner, send) catch {
    Refused(message) => { text: "refused: \{message}\n", code: 1, }
    Api(message) => { text: "failed: \{message}\n", code: 1, }
    Unverified(message) => { text: "unverified: \{message}\n", code: 3, }
  }
}

///|
async fn run_json(
  input : String,
  default_owner : String?,
  send : async (Operation) -> Json raise Failure,
) -> Report raise Failure {
  let json = @json.parse(input) catch {
    _ => raise Refused("the input is not JSON")
  }
  let request = parse_request(json, default_owner)
  run_request({ send, target: request.target, }, request)
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
