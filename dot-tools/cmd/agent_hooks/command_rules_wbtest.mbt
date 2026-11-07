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
    ("eval 'terraform apply'", false, Some("terraform apply")),
    ("eval terraform \"'apply'\"", false, Some("terraform apply")),
    ("eval 'git commit -m \"terraform apply\"'", false, None),
    ("bash -o pipefail -c 'npm publish'", false, Some("npm publish")),
    ("bash +O extglob -c 'npm publish'", false, Some("npm publish")),
    ("bash -eo pipefail -c 'npm publish'", false, Some("npm publish")),
    ("bash --rcfile x -c 'npm publish'", false, Some("npm publish")),
    ("bash -o pipefail script.sh 'npm publish'", false, None),
    // Like the raw grep it replaces, this rule accepts an echo false positive.
    ("echo npm publish", false, Some("npm publish")),
    ("bash script.sh terraform", false, None),
    ("terraform plan", false, None),
    // The verb counts only as the subcommand, past the program's global options.
    ("npm run publish", false, None),
    ("cargo build -p publish", false, None),
    ("terraform plan -target=apply", false, None),
    ("pnpm run publish", false, None),
    ("npm --prefix x publish", false, Some("npm publish")),
    ("npm -w pkg publish", false, Some("npm publish")),
    ("pnpm --filter pkg -r publish", false, Some("npm publish")),
    ("pnpm -C dir publish", false, Some("npm publish")),
    ("cargo +nightly -Z unstable-options publish", false, Some("cargo publish")),
    ("terraform -chdir=x apply", false, Some("terraform apply")),
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
    ("gh -R owner/repo pr create --title t", true, Some("--draft")),
    ("gh --repo owner/repo pr create", true, Some("--draft")),
    ("gh --hostname h pr new --title t", true, Some("--draft")),
    ("gh pr new --draft", true, None),
    // The draft reason wins wherever it is found, as it did with a pass of its own.
    ("npm publish && gh pr create --title t", true, Some("--draft")),
    ("bash -c 'cargo publish'; bash -c 'gh pr new'", true, Some("--draft")),
    ("npm publish && gh pr create --title t", false, Some("npm publish")),
    // Here-document body lines are commands, as on main; quoting a command in a body is an accepted false positive.
    (
      "git commit -F - <<'EOF'\nnpm publish docs\nEOF",
      false,
      Some("npm publish"),
    ),
    (
      "gh pr create --draft --body-file - <<EOF\nRun gh pr create first.\nEOF",
      true,
      Some("--draft"),
    ),
    (
      "tee x <<A <<-\"B\"\nnpm publish\nA\n\tcargo publish\n\tB",
      false,
      Some("npm publish"),
    ),
    ("sh <<EOF\nterraform apply\nEOF", false, Some("terraform apply")),
    ("ssh host <<EOF\nterraform apply\nEOF", false, Some("terraform apply")),
    ("tee <<EOF | timeout 9 bash\nnpm publish\nEOF", false, Some("npm publish")),
    (". /dev/stdin <<EOF\nnpm publish\nEOF", false, Some("npm publish")),
    ("git commit -F- <<< 'x'\nnpm publish", false, Some("npm publish")),
    ("echo $((1<<2))\nnpm publish", false, Some("npm publish")),
    ("cat <<EOF\nplain text\nEOF", false, Some("bat")),
    ("git commit -F - <<'EOF'\nfeat: add x\nEOF", false, None),
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
