///|
async fn main {
  let input = @stdio.stdin.read_all().text() catch { _ => "" }
  guard parse_input(input) is Some(input) else {
    @stdio.stdout.write(unknown)
    return
  }
  let branch = if input.worktree == "" { current_branch(input.cwd) } else { "" }
  let now = @env.now().to_double() / 1000.0
  @stdio.stdout.write(render(input, branch, terminal_width(), now) + "\n")
}
