// Permission rules match command prefixes, so `git push --force *` also caught `--force-with-lease`, and a `+` refspec slipped through every rule.
// This check reads the arguments instead.

///|
pub enum Decision {
  Ask(String)
  Deny(String)
}

///|
/// Finds the first forced `git push` or `git add` in a Bash command.
/// `--force-with-lease` passes, while `--force`, `-f` and `+` refspecs ask, or are denied when `deny_force_push` is set.
pub fn decide(command : String, deny_force_push~ : Bool) -> Decision? {
  for segment in @git_command.segments(command) {
    guard @git_command.subcommand(segment) is Some((_, subcommand, args)) else {
      continue
    }

    if subcommand == "add" && is_forced_add(args) {
      return Some(
        Deny(
          "git add --force/-f is blocked to prevent committing git-excluded files. Remove the -f/--force flag.",
        ),
      )
    }

    if subcommand == "push" && is_forced_push(args) {
      return Some(
        if deny_force_push {
          Deny(
            "git push --force, -f and +refspec are blocked. Use --force-with-lease instead.",
          )
        } else {
          Ask("git push --force, -f or +refspec overwrites the remote branch.")
        },
      )
    }
  }
  None
}

///|
let push_options_with_value : Array[String] = [
  "-o", "--push-option", "--repo", "--receive-pack", "--exec",
]

///|
fn is_forced_push(args : ArrayView[String]) -> Bool {
  let mut skip_value = false
  let mut options_ended = false
  for arg in args {
    if skip_value {
      skip_value = false
      continue
    }

    if options_ended || !arg.has_prefix("-") {
      if arg.has_prefix("+") {
        return true
      }
      continue
    }

    if arg == "--" {
      options_ended = true
    } else if arg == "--force" {
      return true
    } else if push_options_with_value.contains(arg) {
      skip_value = true
    } else if !arg.has_prefix("--") {
      // In a cluster such as `-uo`, the letters after `o` are its value, not more flags.
      let letters = short_flags(arg, value_flag='o')
      if letters.contains_char('f') {
        return true
      }
      skip_value = letters.has_suffix("o") && arg.has_suffix("o")
    }
  }
  false
}

///|
let add_force_long : Array[String] = ["--for", "--forc", "--force"]

///|
fn is_forced_add(args : ArrayView[String]) -> Bool {
  for arg in args {
    if arg == "--" {
      return false
    }
    if add_force_long.contains(arg) {
      return true
    }
    if arg.has_prefix("-") && !arg.has_prefix("--") && arg.contains_char('f') {
      return true
    }
  }
  false
}

///|
fn short_flags(arg : String, value_flag~ : Char) -> String {
  let letters = StringBuilder()
  for char in arg.iter().drop(1) {
    letters.write_char(char)
    if char == value_flag {
      break
    }
  }
  letters.to_string()
}
