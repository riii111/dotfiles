// Shows local branches as a tree rooted at main or master, matching the Python script it replaced.

///|
extern "C" fn exit(code : Int32) = "exit"

///|
extern "C" fn isatty(fd : Int32) -> Int32 = "isatty"

///|
async fn main {
  let color = isatty(1) != 0 && @env.get_env_var("NO_COLOR") is None
  let code = run(Git::new(None), color~)
  exit(code)
}

///|
async fn run(git : Git, color~ : Bool) -> Int32 {
  let tree = branch_tree(git, color~) catch {
    GitFailed(message) => {
      @stdio.stderr.write("error: \{message}\n")
      return 1
    }
    error => {
      @stdio.stderr.write("error: \{error}\n")
      return 1
    }
  }
  guard tree is Some(tree) else {
    @stdio.stderr.write("error: neither main nor master branch found\n")
    return 1
  }
  @stdio.stdout.write(tree)
  0
}

///|
priv suberror GitFailed {
  GitFailed(String)
}

///|
/// Git commands run in `cwd`, or in the current directory when it is `None`.
/// Outputs are cached per argument list because the parent search repeats the same commands for every branch.
priv struct Git {
  cwd : String?
  outputs : Map[String, String?]
  checks : Map[String, Bool]
}

///|
fn Git::new(cwd : String?) -> Git {
  { cwd, outputs: Map([]), checks: Map([]), }
}

///|
async fn Git::status(self : Git, args : Array[String]) -> (Int32, &@io.Data) {
  let (status, stdout, _) = @process.collect_output(
    "git",
    args,
    cwd?=self.cwd.map(cwd => cwd[:]),
  )
  (status, stdout)
}

///|
/// Returns the trimmed stdout of a successful command, or `None` when it exits with a nonzero status.
async fn Git::output(self : Git, args : Array[String]) -> String? {
  let key = args.join("\u{0}")
  if self.outputs.get(key) is Some(cached) {
    return cached
  }
  let (status, stdout) = self.status(args)
  let output = if status == 0 {
    Some(@utf8.decode_lossy(stdout.binary()).trim().to_owned())
  } else {
    None
  }
  self.outputs[key] = output
  output
}

///|
async fn Git::required(self : Git, args : Array[String]) -> String {
  guard self.output(args) is Some(output) else {
    raise GitFailed("git \{args.join(" ")} failed")
  }
  output
}

///|
async fn Git::succeeds(self : Git, args : Array[String]) -> Bool {
  let key = args.join("\u{0}")
  if self.checks.get(key) is Some(cached) {
    return cached
  }
  let (status, _) = self.status(args)
  self.checks[key] = status == 0
  status == 0
}

///|
async fn count_commits(
  git : Git,
  start : String,
  end : String,
  first_parent~ : Bool = false,
) -> Int32? {
  let args = ["rev-list", "--count"]
  if first_parent {
    args.push("--first-parent")
  }
  args.push("\{start}..\{end}")
  match git.output(args) {
    Some(output) => Some(@string.parse_int(output))
    None => None
  }
}

///|
async fn branch_birth_time(git : Git, branch : String) -> Int64? {
  guard git.output(["reflog", "show", "--format=%ct", branch]) is Some(output) &&
    output != "" else {
    return None
  }
  let lines = output.split("\n").collect()
  Some(@string.parse_int64(lines[lines.length() - 1]))
}

///|
/// Python ranks a fork point found in the candidate's reflog before an ancestor tip.
priv enum Mode {
  ForkPoint
  AncestorTip
} derive(Eq, Compare)

///|
priv struct Candidate {
  mode : Mode
  distance : Int32
  first_parent_distance : Int32
  candidate_distance : Int32
  branch_depth : Int32
}

///|
async fn parent_candidate(
  git : Git,
  root : String,
  candidate : String,
  branch : String,
) -> Candidate? {
  let (branch_point, mode) = match
    git.output(["merge-base", "--fork-point", candidate, branch]) {
    Some(point) => (point, ForkPoint)
    None => {
      guard git.output(["rev-parse", candidate]) is Some(tip) &&
        git.output(["merge-base", candidate, branch]) is Some(merge_base) &&
        merge_base == tip else {
        return None
      }
      (tip, AncestorTip)
    }
  }
  guard count_commits(git, branch_point, branch) is Some(distance) &&
    distance > 0 else {
    return None
  }
  guard count_commits(git, branch_point, branch, first_parent=true)
    is Some(first_parent_distance) else {
    return None
  }
  guard count_commits(git, branch_point, candidate, first_parent=true)
    is Some(candidate_distance) else {
    return None
  }
  let branch_depth = count_commits(git, root, branch_point).unwrap_or(0)
  Some({
    mode,
    distance,
    first_parent_distance,
    candidate_distance,
    branch_depth,
  })
}

///|
/// Orders by code point like Python's string comparison; `String::compare` orders shorter strings first.
fn code_point_compare(a : String, b : String) -> Int32 {
  let a = a.iter().collect()
  let b = b.iter().collect()
  let length = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<length {
    if a[i] != b[i] {
      return a[i].compare(b[i])
    }
  }
  a.length().compare(b.length())
}

///|
/// Python sorted unknown and zero birth times (`birth or inf`) after every real one.
fn birth_order(birth : Int64?) -> (Bool, Int64) {
  match birth {
    None => (true, @int64.MAX_VALUE)
    Some(0) => (false, @int64.MAX_VALUE)
    Some(time) => (false, time)
  }
}

///|
/// Maps each branch with a worktree to its worktree path.
async fn worktrees(git : Git) -> Map[String, String] {
  let worktrees = Map([])
  guard git.output(["worktree", "list", "--porcelain"]) is Some(output) else {
    return worktrees
  }
  let mut path = ""
  for line in output.split("\n") {
    if line.strip_prefix("worktree ") is Some(value) {
      path = value.to_owned()
    } else if line.strip_prefix("branch refs/heads/") is Some(branch) &&
      path != "" {
      worktrees[branch.to_owned()] = path
    }
  }
  worktrees
}

///|
/// Returns the rendered tree, or `None` when the repository has neither `main` nor `master`.
async fn branch_tree(git : Git, color~ : Bool) -> String? {
  let mut root = None
  for candidate in ["main", "master"] {
    if git.output(["rev-parse", "--verify", candidate]) is Some(_) {
      root = Some(candidate)
      break
    }
  }
  guard root is Some(root) else { return None }

  // A detached HEAD is listed as `(HEAD detached at ...)` and stays in the tree under the root, as in the Python script.
  let branches = git
    .required(["branch", "--format=%(refname:short)"])
    .split("\n")
    .filter(branch => branch != "" && branch != root)
    .map(branch => branch.to_owned())
    .collect()
  let current = git.required(["branch", "--show-current"])
  let order_keys : Map[String, ((Bool, Int64), Int32)] = Map([])
  for branch in branches {
    let birth = birth_order(branch_birth_time(git, branch))
    let root_distance = count_commits(git, root, branch).unwrap_or(0)
    order_keys[branch] = (birth, root_distance)
  }
  let worktrees = worktrees(git)

  let ordered = branches.copy()
  ordered.sort_by((a, b) => {
    match order_keys[a].compare(order_keys[b]) {
      0 => code_point_compare(a, b)
      order => order
    }
  })
  let children : Map[String, Array[String]] = Map([(root, [])])
  let commit_counts : Map[String, Int32] = Map([])
  let placed = []
  for branch in ordered {
    let mut best : (String, Candidate)? = None
    for candidate in [root, ..placed] {
      if git.succeeds(["merge-base", "--is-ancestor", branch, candidate]) {
        continue
      }
      guard parent_candidate(git, root, candidate, branch) is Some(found) else {
        continue
      }
      if best is Some(current_best) && !better(candidate, found, current_best) {
        continue
      }
      best = Some((candidate, found))
    }
    let parent = match best {
      Some((parent, found)) => {
        commit_counts[branch] = found.distance
        parent
      }
      None => {
        commit_counts[branch] = count_commits(git, root, branch).unwrap_or(0)
        root
      }
    }
    match children.get(parent) {
      Some(siblings) => siblings.push(branch)
      None => children[parent] = [branch]
    }
    placed.push(branch)
  }

  let palette = if color {
    { current: "\u{1b}[1;32m", worktree: "\u{1b}[36m", reset: "\u{1b}[0m", }
  } else {
    { current: "", worktree: "", reset: "", }
  }
  let nodes = { current, worktrees, commit_counts, children, palette, }
  let output = StringBuilder()
  output.write_string("\n")
  nodes.write(output, root, "", true, true)
  output.write_string("\n")
  Some(output.to_string())
}

///|
fn better(name : String, found : Candidate, best : (String, Candidate)) -> Bool {
  let (best_name, best) = best
  let key = (
    found.mode,
    found.first_parent_distance,
    found.candidate_distance,
    found.distance,
    -found.branch_depth,
  )
  let best_key = (
    best.mode,
    best.first_parent_distance,
    best.candidate_distance,
    best.distance,
    -best.branch_depth,
  )
  match key.compare(best_key) {
    0 => code_point_compare(name, best_name) < 0
    order => order < 0
  }
}

///|
priv struct Palette {
  current : String
  worktree : String
  reset : String
}

///|
priv struct Nodes {
  current : String
  worktrees : Map[String, String]
  commit_counts : Map[String, Int32]
  children : Map[String, Array[String]]
  palette : Palette
}

///|
fn Nodes::label(self : Nodes, node : String, is_root : Bool) -> String {
  let is_current = node == self.current
  let worktree = if is_current { None } else { self.worktrees.get(node) }
  let parts = [node]
  if !is_root {
    parts.push("(+\{self.commit_counts[node]})")
  }
  if worktree is Some(path) {
    let name = match path.rev_find("/") {
      Some(index) => path[index + 1:].to_owned()
      None => path
    }
    parts.push("● \{name}")
  }
  if is_current {
    parts.push("★")
  }
  let label = parts.join(" ")
  if is_current {
    self.palette.current + label + self.palette.reset
  } else if worktree is Some(_) {
    self.palette.worktree + label + self.palette.reset
  } else {
    label
  }
}

///|
fn Nodes::write(
  self : Nodes,
  output : StringBuilder,
  node : String,
  prefix : String,
  is_last : Bool,
  is_root : Bool,
) -> Unit {
  if is_root {
    output.write_string("  \{self.label(node, true)}\n")
  } else {
    let marker = if is_last { "└── " } else { "├── " }
    output.write_string("  \{prefix}\{marker}\{self.label(node, false)}\n")
  }
  let children = self.children.get(node).unwrap_or([])
  for i, child in children {
    let child_prefix = if is_root {
      ""
    } else if is_last {
      prefix + "    "
    } else {
      prefix + "│   "
    }
    self.write(output, child, child_prefix, i == children.length() - 1, false)
  }
}
