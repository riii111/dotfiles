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
    ("git commit -m \"terraform apply\"", false, None),
    // A program anywhere in the command counts, so wrappers with options cannot hide it.
    ("timeout 600 terraform apply", false, Some("terraform apply")),
    ("env -u X terraform apply", false, Some("terraform apply")),
    ("sudo -E npm publish", false, Some("npm publish")),
    ("nice cargo publish", false, Some("cargo publish")),
    ("xargs terraform destroy", false, Some("terraform destroy")),
    ("/usr/bin/env npm publish", false, Some("npm publish")),
    ("bash -c 'terraform apply'", false, Some("terraform apply")),
    ("zsh -lc 'cd x && cargo publish'", false, Some("cargo publish")),
    ("sh -c \"bash -c 'npm publish'\"", false, Some("npm publish")),
    ("bash -c 'git commit -m \"terraform apply\"'", false, None),
    // Like the raw grep it replaces, this rule accepts an echo false positive.
    ("echo npm publish", false, Some("npm publish")),
    ("bash script.sh terraform", false, None),
    ("terraform plan", false, None),
    ("gh pr create --title t", true, Some("--draft")),
    ("gh pr create --title t", false, None),
    ("gh pr create --draft --title t", true, None),
    ("gh pr create -d --title t", true, None),
    ("git commit -m 'gh pr create'", true, None),
    ("timeout 60 gh pr create --title t", true, Some("--draft")),
    ("env -u X gh pr create", true, Some("--draft")),
    ("sudo -E gh pr create", true, Some("--draft")),
    ("bash -c 'gh pr create --title t'", true, Some("--draft")),
    ("bash -c 'gh pr create --draft'", true, None),
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
