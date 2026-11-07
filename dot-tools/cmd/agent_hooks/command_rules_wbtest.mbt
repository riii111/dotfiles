///|
test "denies by the parsed command, not by text inside arguments" {
  let cases : Array[(String, Bool, String?)] = [
    ("find . -name x", false, Some("fd")),
    ("grep -r x .", false, Some("rg")),
    ("cat README.md", false, Some("bat")),
    ("ls | grep x", false, None),
    ("catalog list", false, None),
    (
      "gh pr create --title t --body \"$(cat <<'EOF'\nbody\nEOF\n)\"",
      false,
      None,
    ),
    ("terraform apply", false, Some("terraform apply")),
    ("cd infra && terraform -chdir=x destroy", false, Some("terraform destroy")),
    ("FOO=1 npm publish", false, Some("npm publish")),
    ("pnpm publish", false, Some("npm publish")),
    ("cargo publish --dry-run", false, Some("cargo publish")),
    ("git commit -m 'terraform apply'", false, None),
    ("echo npm publish", false, None),
    ("terraform plan", false, None),
    ("gh pr create --title t", true, Some("--draft")),
    ("gh pr create --title t", false, None),
    ("gh pr create --draft --title t", true, None),
    ("gh pr create -d --title t", true, None),
    ("git commit -m 'gh pr create'", true, None),
  ]
  for case in cases {
    let (command, require_draft, expected) = case
    let reason = command_rule_denial(command, require_draft~)
    match (expected, reason) {
      (None, None) => ()
      (Some(part), Some(reason)) if reason.contains(part) => ()
      _ => fail("unexpected reason for \{command}")
    }
  }
}
