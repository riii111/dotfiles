///|
/// The script a command runs as shell input: `eval` joins its arguments with spaces, as the shell does.
pub fn nested_script(words : ArrayView[String]) -> String? {
  match words {
    [program, .. args] if basename(program) == "eval" =>
      Some(args.iter().collect().join(" "))
    _ => shell_command(words)
  }
}

///|
let shells : Array[String] = ["sh", "bash", "zsh", "dash", "ksh"]

///|
/// Long shell options that consume the next word.
let shell_long_options_with_value : Array[String] = ["--rcfile", "--init-file"]

///|
/// The script of `sh -c SCRIPT`, also with combined options like `-lc` or `-ec`,
/// past options taking a value (`-o pipefail`, `+O extglob`, `--rcfile FILE`).
fn shell_command(words : ArrayView[String]) -> String? {
  guard words is [program, .. args] && shells.contains(basename(program)) else {
    return None
  }
  let mut inline = false
  let mut skip = 0
  for arg in args {
    if skip > 0 {
      skip -= 1
    } else if shell_long_options_with_value.contains(arg) {
      skip = 1
    } else if arg.has_prefix("--") {
      continue
    } else if (arg.has_prefix("-") || arg.has_prefix("+")) && arg.length() > 1 {
      inline = inline || arg.contains_char('c')
      // Each `o` or `O` in a cluster such as `-eo` takes the next word.
      for char in arg {
        if char == 'o' || char == 'O' {
          skip += 1
        }
      }
    } else {
      return if inline { Some(arg) } else { None }
    }
  }
  None
}
