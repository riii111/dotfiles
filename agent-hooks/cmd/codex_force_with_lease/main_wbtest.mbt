///|
/// Runs `force_with_lease` against canned Git output and returns the outcome with every Git call.
async fn run_with(
  stdout : (String) -> String,
  trusted~ : Bool = true,
) -> (Outcome, Array[Array[String]]) {
  let calls = []
  let outcome = force_with_lease(trusted~, args => {
    calls.push(args)
    { status: 0, stdout: stdout(args[0]), stderr: "", }
  })
  (outcome, calls)
}

///|
fn pushed(calls : Array[Array[String]]) -> Bool {
  calls.iter().any(args => args[0] == "push")
}

///|
async test "an untrusted repository is not pushed" {
  let (outcome, calls) = run_with(_ => "feat/test\n", trusted=false)
  assert_eq(outcome.exit_code(), 1)
  assert_true(calls.is_empty())
}

///|
async test "a protected branch is not pushed" {
  let (outcome, calls) = run_with(_ => "main\n")
  assert_eq(outcome.exit_code(), 1)
  assert_false(pushed(calls))
}

///|
async test "a missing remote branch is not created" {
  let (outcome, calls) = run_with(command => {
    if command == "symbolic-ref" {
      "feat/test\n"
    } else {
      ""
    }
  })
  assert_eq(outcome.exit_code(), 1)
  assert_false(pushed(calls))
}

///|
async test "the push is leased on the remote OID" {
  let old_oid = "1".repeat(40)
  let local_oid = "2".repeat(40)
  let (outcome, calls) = run_with(command => {
    match command {
      "symbolic-ref" => "feat/test\n"
      "ls-remote" =>
        "\{old_oid.to_upper()}\trefs/heads/feat/test\n\{"3".repeat(40)}\trefs/heads/feat/test2\n"
      "rev-parse" => "\{local_oid}\n"
      _ => ""
    }
  })
  assert_eq(outcome.exit_code(), 0)
  let push = calls.iter().find_first(args => args[0] == "push").unwrap()
  assert_eq(push, [
    "push",
    "origin",
    "--force-with-lease=refs/heads/feat/test:\{old_oid}",
    "\{local_oid}:refs/heads/feat/test",
  ])
}
