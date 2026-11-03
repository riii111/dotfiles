///|
/// The operation of a GitHub MCP tool, such as `create_pull_request` for `mcp__github__create_pull_request`, or `None` for another tool.
/// The Codex connector names its operations `github_` or `github.` followed by the name.
pub fn operation(name : String) -> String? {
  guard name.has_prefix("mcp__") && name.contains("github") else { return None }
  let operation = match name.rev_split_once("__") {
    Some((_, operation)) => operation.to_owned()
    None => name
  }
  match operation.strip_prefix("github") {
    Some(rest) if rest.has_prefix(".") || rest.has_prefix("_") =>
      Some(rest.view(start_offset=1).to_owned())
    _ => Some(operation)
  }
}
