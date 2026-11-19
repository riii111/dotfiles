///|
test "force-with-lease passes" {
  let commands = [
    "git push --force-with-lease", "git push --force-with-lease=feat/x origin HEAD:feat/x",
    "git push --force-with-lease --force-if-includes origin feat/x", "cd repo && git push --force-with-lease 2>&1",
  ]
  for command in commands {
    assert_true(@git_force.decide(command, deny_force_push=true) is None)
  }
}

///|
test "forced push asks or is denied" {
  let commands = [
    "git push --force", "git push origin feat/x --force", "git push -f origin feat/x",
    "git push -uf origin feat/x", "git push origin +feat/x", "git push --force-with-lease origin +feat/x",
    "git -C repo push origin +HEAD:feat/x", "git status && git push -f", "git status\ngit push origin +feat/x",
    // A global option with a separate value must not hide the subcommand.
     "git --config-env core.x=Y push -f", "git --git-dir .git --work-tree . push --force",
    // A body fed to a shell runs as commands.
     "bash <<'EOF'\ngit push --force origin main\nEOF", "ssh host <<EOF\ngit push --force origin main\nEOF",
    "echo $((1<<2))\ngit push --force origin main\n2",
  ]
  for command in commands {
    assert_true(
      @git_force.decide(command, deny_force_push=false) is Some(Ask(_)),
    )
    assert_true(
      @git_force.decide(command, deny_force_push=true) is Some(Deny(_)),
    )
  }
}

///|
test "normal push passes" {
  let commands = [
    "git push", "git push -u origin feat/x", "git push -o ci.skip origin feat/x",
    "git push origin -- feat/x", "git commit -m \"allow git push -f\" && git push",
  ]
  for command in commands {
    assert_true(@git_force.decide(command, deny_force_push=true) is None)
  }
}

///|
test "forced add is denied" {
  let commands = [
    "git add -f x", "git add --force x", "git add --for x", "git add -Af",
  ]
  for command in commands {
    assert_true(
      @git_force.decide(command, deny_force_push=false) is Some(Deny(_)),
    )
  }
}

///|
test "add ignores force in later lines" {
  let commands = [
    "git add x\ngit push --force-with-lease", "git add x && git commit -m 'use --force'",
    "git add -- -f",
  ]
  for command in commands {
    assert_true(@git_force.decide(command, deny_force_push=false) is None)
  }
}
