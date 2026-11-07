///|
let segment_breaks : Array[String] = [";", "&", "|", "(", ")"]

///|
/// Checks every `git` word of a compound command up to the next single `;`, `&`, `|`, `(` or `)` word.
/// A run like `&&` is one word that does not end the segment, as with `shlex`.
async fn compound_denial_reason(
  command : String,
  has_config : async (String) -> Bool,
) -> String? {
  let tokens = @shell.split_words(command, punctuation="();&|", comments=false) catch {
    _ => return None
  }
  for index, token in tokens {
    guard @shell.basename(token) == "git" else { continue }
    let segment = []
    for candidate in tokens[index + 1:] {
      if segment_breaks.contains(candidate) {
        break
      }
      segment.push(candidate)
    }
    if has_external_helper_config(segment) {
      return Some("External Git diff helpers are forbidden.")
    }
    if has_git_config_override(segment) {
      return Some("Git config overrides are forbidden.")
    }
    guard git_command(segment) is Some((subcommand, subargs)) else { continue }
    if git_denial_reason(subcommand, subargs) is Some(reason) {
      return Some(reason)
    }
    if unsafe_git_configuration(subcommand, subargs, has_config) {
      return Some("Unsafe Git configuration is forbidden.")
    }
  }
  let chars : Array[Char] = command.iter().collect()
  if mentions_hard_reset(chars) {
    return Some("Hard reset is forbidden.")
  }
  if mentions_forced_add(chars) {
    return Some("Force-add is forbidden.")
  }
  if mentions_recursive_rm(chars) {
    return Some("Recursive file deletion is forbidden.")
  }
  if tokens.iter().any(token => token.has_prefix("GIT_EXTERNAL_DIFF=")) {
    return Some("External Git diff helpers are forbidden.")
  }
  None
}
