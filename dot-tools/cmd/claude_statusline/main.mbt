///|
async fn main {
  let input = @stdio.stdin.read_all().text() catch { _ => "" }
  guard @statusline.parse_input(input) is Some(input) else {
    @stdio.stdout.write(@statusline.unknown)
    return
  }
  let branch = if input.worktree == "" {
    @statusline.current_branch(input.cwd)
  } else {
    ""
  }
  let now = @env.now().to_double() / 1000.0
  @stdio.stdout.write(
    @statusline.render(input, branch, @statusline.terminal_width(), now) + "\n",
  )
}
