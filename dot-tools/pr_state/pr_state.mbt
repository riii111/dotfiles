// Protects review approvals and merges; a pull request whose identity is uncertain never authorizes a mutation.
// The GitHub MCP server that Claude Code cloud sessions use is held to the same rules: its merges ask outside personal
// repositories, and since this hook cannot ask it whether a pull request is a draft, its base changes and conversions to
// draft are denied.

///|
pub(all) enum Decision {
  Ask
  Deny
}

///|
/// A `gh pr view` the check runs to learn a pull request's draft state or repository.
pub(all) struct Lookup {
  gh : String
  args : Array[String]
  cwd : String
  environment : Map[String, String]
  timeout_ms : Int32
}

///|
/// Personal repositories merge without asking; any other owner's pull request waits for the owner.
let merge_free_owners : Array[String] = ["riii111"]

///|
pub let merge_reason : String = "マージはownerの確認が必要です。ownerに頼まれたマージだけを実行してください。"

///|
let draft_reason : String = "Open済みPRのDraft化・base変更は禁止。承認を保つため操作を止めました。"

///|
let unknown_reason : String = "PRがDraftか確認できないため操作を止めました。対象PR・リポジトリ・接続を確認してください。"

///|
let mcp_draft_unknown : String = "GitHub MCPではPRがDraftか確認できないため、base変更・Draft化を止めました。必要ならownerに頼んでください。"

///|
let value_flags : Array[String] = [
  "-R", "--repo", "-B", "--base", "-b", "--body", "-F", "--body-file", "-t", "--title",
  "-m", "--milestone", "--add-label", "--remove-label", "--add-assignee", "--remove-assignee",
  "--add-reviewer", "--remove-reviewer", "--add-project", "--remove-project", "--attach",
  "--subject", "--match-head-commit", "-A", "--author-email",
]

///|
let lookup_budget_ms : UInt64 = 10000

///|
/// Checks a Bash command; `merge` is the decision for a merge outside personal repositories.
/// `lookup` runs `gh pr view` and returns its standard output, raising when it fails.
pub async fn check(
  command : String,
  cwd : String,
  merge~ : Decision,
  lookup : async (Lookup) -> String,
) -> (Decision, String)? {
  guard mentions_mutation(command) else { return None }
  let merging = Ref(false)
  check_segments(command, cwd, merge~, merging, lookup) catch {
    _ =>
      Some(
        if merging.val {
          (merge, merge_reason)
        } else {
          (Deny, unknown_reason)
        },
      )
  }
}

///|
/// Mirrors the Python prefilter `\bgh\b.*\b(?:pr\b.*\b(?:ready|edit|merge)|api)\b`.
fn mentions_mutation(command : String) -> Bool {
  guard @text.word_at(command, "gh") is Some(gh) else { return false }
  let after = gh + 2
  if @text.has_word(command, "api", from=after) {
    return true
  }
  guard @text.word_at(command, "pr", from=after) is Some(pr) else {
    return false
  }
  ["ready", "edit", "merge"]
  .iter()
  .any(word => @text.has_word(command, word, from=pr + 2))
}

///|
async fn check_segments(
  command : String,
  cwd : String,
  merge~ : Decision,
  merging : Ref[Bool],
  lookup : async (Lookup) -> String,
) -> (Decision, String)? {
  let deadline = @env.now() + lookup_budget_ms
  let mut cwd = cwd
  let directories = []
  for part in segments(command) {
    if part is ["("] {
      directories.push(cwd)
      continue
    }
    if part is [")"] {
      guard directories.pop() is Some(previous) else {
        raise Uncertain("unbalanced subshell")
      }
      cwd = previous
      continue
    }
    if part[0] == "cd" {
      guard part is [_, target] && !target.contains_any(chars="$`~") else {
        raise Uncertain("working directory is dynamic")
      }
      cwd = resolve(
        if target.has_prefix("/") {
          target
        } else {
          cwd + "/" + target
        },
      )
      continue
    }

    let environment = @env.get_env_vars()
    let mut words = part[:]
    while words is [first, .. rest] &&
          (is_assignment(first) || first == "env" || first == "command") {
      if first.split_once("=") is Some((key, value)) {
        if value.contains_any(chars="$`") {
          raise Uncertain("environment is dynamic")
        }
        environment[key.to_owned()] = value.to_owned()
      }
      words = rest
    }
    guard words is [gh, .. args] && base_name(gh) == "gh" else { continue }

    let (prefix, args) = take_repo(args)
    if args is ["api", .. api_args] {
      if api_merge_owner(api_args) is Some(owner) &&
        !merge_free_owners.contains(owner) {
        return Some((merge, merge_reason))
      }
      continue
    }
    guard args is ["pr", .. pr_args] else { continue }
    let (parent_repo, args) = take_repo(pr_args)
    guard args is [subcommand, .. options] &&
      (subcommand == "edit" || subcommand == "ready" || subcommand == "merge") else {
      continue
    }
    if args.contains("--help") || args.contains("-h") {
      continue
    }
    merging.val = merging.val || subcommand == "merge"
    let (query, dangerous) = query_args([..prefix, ..parent_repo, ..options])
    guard subcommand == "merge" || dangerous else { continue }

    let now = @env.now()
    guard now < deadline else { raise Uncertain("lookup deadline exceeded") }
    let remaining = (deadline - now).to_int()
    let field = if subcommand == "merge" { "url" } else { "isDraft" }
    let output = @json.parse(
      lookup({
        gh,
        args: ["pr", "view", ..query, "--json", field],
        cwd,
        environment,
        timeout_ms: if remaining < 5000 {
          remaining
        } else {
          5000
        },
      }),
    )
    if subcommand == "merge" {
      guard output is { "url": String(url), .. } &&
        github_owner(url) is Some(owner) else {
        raise Uncertain("PR URL is not on GitHub")
      }
      if !merge_free_owners.contains(owner) {
        return Some((merge, merge_reason))
      }
      continue
    }
    guard output is Object(fields) else {
      raise Uncertain("unexpected gh output")
    }
    if !(fields.get("isDraft") is Some(True)) {
      return Some((Deny, draft_reason))
    }
  }
  None
}

///|
fn is_assignment(word : String) -> Bool {
  guard word.find("=") is Some(index) && index > 0 else { return false }
  word.view(end_offset=index).iter().all(@text.is_word_char)
}

///|
/// The last component of a path, like Python's `Path.name`.
fn base_name(path : String) -> String {
  let trimmed = path.trim_end(chars="/").to_owned()
  match trimmed.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => trimmed
  }
}

///|
/// Splits a leading `-R`/`--repo` option from `args`.
fn take_repo(args : ArrayView[String]) -> (Array[String], ArrayView[String]) {
  match args {
    [flag, value, .. rest] if flag == "-R" || flag == "--repo" =>
      ([flag, value], rest)
    ["-R" | "--repo"] => (args.to_owned(), [][:])
    [first, .. rest] if first.has_prefix("--repo=") || first.has_prefix("-R") =>
      ([first], rest)
    _ => ([], args)
  }
}

///|
/// Returns the arguments that name the same pull request for `gh pr view`, and whether the command changes its base or makes it a draft.
fn query_args(args : Array[String]) -> (Array[String], Bool) raise Uncertain {
  let mut repo = []
  let targets = []
  let mut dangerous = false
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    let (flag, inline_value) = match arg.split_once("=") {
      Some((flag, value)) => (flag.to_owned(), Some(value.to_owned()))
      None => (arg, None)
    }
    if flag == "--undo" ||
      flag == "--base" ||
      flag == "-B" ||
      arg.has_prefix("-B") {
      dangerous = true
    }
    if value_flags.contains(flag) {
      let value = match inline_value {
        Some(value) => value
        None => {
          index += 1
          guard args.get(index) is Some(value) else {
            raise Uncertain("option without a value")
          }
          value
        }
      }
      if flag == "-R" || flag == "--repo" {
        repo = ["--repo", value]
      }
    } else if arg.has_prefix("-R") {
      repo = ["--repo", arg.view(start_offset=2).to_owned()]
    } else if !arg.has_prefix("-") {
      targets.push(arg)
    }
    index += 1
  }
  let identity = [..targets, ..repo]
  if targets.length() > 1 ||
    identity.iter().any(item => item.contains_any(chars="$`")) {
    raise Uncertain("PR identity is dynamic or ambiguous")
  }
  (identity, dangerous)
}

///|
/// The owner of a merge through `gh api`: `Some("")` when its owner is unknown, `None` when it is no merge.
fn api_merge_owner(args : ArrayView[String]) -> String? {
  // A GET on the merge endpoint only asks whether the pull request is merged.
  let mut put = false
  for index, arg in args {
    let upper = arg.to_upper()
    if upper == "-XPUT" || upper == "--METHOD=PUT" {
      put = true
    }
    if (arg == "-X" || arg == "--method") &&
      args.get(index + 1) is Some(verb) &&
      verb.to_upper() == "PUT" {
      put = true
    }
  }
  let mut owner = None
  for arg in args {
    let value = match arg.split_once("=") {
      Some((_, value)) if arg.has_prefix("-") => value.to_owned()
      _ => arg
    }
    if @text.has_word(value, "mergePullRequest") ||
      @text.has_word(value, "enablePullRequestAutoMerge") {
      return Some("")
    }
    if put && merge_endpoint_owner(value) is Some(found) {
      owner = Some(found)
    }
  }
  owner
}

///|
/// Mirrors `(?:^|/)repos/(?P<owner>[\w.-]+)/[\w.-]+/pulls/\d+/merge$`.
fn merge_endpoint_owner(value : String) -> String? {
  let value = value
    .strip_suffix("\n")
    .map(view => view.to_owned())
    .unwrap_or(value)
  let mut from = 0
  while value.view(start_offset=from).find("repos/") is Some(offset) {
    let start = from + offset
    from = start + 1
    if start > 0 && value.code_unit_at(start - 1) != '/' {
      continue
    }
    let parts = value
      .view(start_offset=start + 6)
      .to_owned()
      .split("/")
      .map(part => part.to_owned())
      .collect()
    guard parts is [owner, repo, "pulls", number, "merge"] else { continue }
    if is_name(owner) &&
      is_name(repo) &&
      number != "" &&
      number.iter().all(@text.is_decimal) {
      return Some(owner)
    }
  }
  None
}

///|
fn is_name(text : String) -> Bool {
  text != "" &&
  text
  .iter()
  .all(char => @text.is_word_char(char) || char == '.' || char == '-')
}

///|
fn github_owner(url : String) -> String? {
  guard url.strip_prefix("https://github.com/") is Some(rest) else {
    return None
  }
  guard rest.to_owned().split_once("/") is Some((owner, _)) && owner != "" else {
    return None
  }
  Some(owner.to_owned())
}

///|
/// Resolves symlinks in an existing `path`; a missing one is only normalized, like Python's non-strict `Path.resolve()`.
async fn resolve(path : String) -> String {
  @fs.realpath(path) catch {
    _ => normalize(path)
  }
}

///|
fn normalize(path : String) -> String {
  let parts = []
  for part in path.split("/") {
    match part.to_owned() {
      "" | "." => ()
      ".." => ignore(parts.pop())
      name => parts.push(name)
    }
  }
  "/" + parts.join("/")
}

///|
let mcp_merges : Array[String] = ["merge_pull_request", "enable_pr_auto_merge"]

///|
/// Checks a GitHub MCP tool call.
pub fn mcp_check(
  name : String,
  input : Json,
  merge~ : Decision,
) -> (Decision, String)? {
  guard @github_tool.operation(name) is Some(operation) else { return None }
  if mcp_merges.contains(operation) {
    if input is { "owner": String(owner), .. } &&
      merge_free_owners.contains(owner) {
      return None
    }
    return Some((merge, merge_reason))
  }
  if operation == "update_pull_request" &&
    (input is { "base": _, .. } || input is { "draft": True, .. }) {
    return Some((Deny, mcp_draft_unknown))
  }
  None
}

///|
/// Runs a lookup with its own environment and time limit, raising when `gh` fails.
pub async fn run_lookup(request : Lookup) -> String {
  let (status, stdout, _) = @async.with_timeout(request.timeout_ms, () => {
    @process.collect_output(
      request.gh,
      request.args,
      extra_env=request.environment,
      inherit_env=false,
      cwd=request.cwd,
    )
  })
  guard status == 0 else { raise Uncertain("gh failed") }
  stdout.text()
}
