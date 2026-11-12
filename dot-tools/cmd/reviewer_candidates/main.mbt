// Lists the people who committed most to some paths, so a reviewer can be picked from those who know them.

///|
extern "C" fn exit(code : Int32) = "exit"

///|
let usage : String = "usage: reviewer-candidates [--limit N] [--since DATE] [--base REF] [PATH...]\n"

///|
async fn main {
  exit(run(@env.args().iter().drop(1).collect(), None))
}

///|
async fn run(args : Array[String], cwd : String?) -> Int32 {
  let options = parse_options(args) catch {
    Usage(message) => {
      @stdio.stderr.write("error: \{message}\n\{usage}")
      return 2
    }
  }
  guard options is Some(options) else {
    @stdio.stdout.write(usage)
    return 0
  }
  let report = candidates({ cwd, }, options) catch {
    Failed(message) => {
      @stdio.stderr.write("error: \{message}\n")
      return 1
    }
    error => {
      @stdio.stderr.write("error: \{error}\n")
      return 1
    }
  }
  @stdio.stdout.write(report)
  0
}

///|
priv struct Options {
  limit : Int32
  since : String
  base : String?
  paths : Array[String]
}

///|
priv suberror Usage {
  Usage(String)
}

///|
/// Returns `None` when help is asked for.
fn parse_options(args : Array[String]) -> Options? raise Usage {
  let mut limit = 5
  // Authors who left long ago cannot review, so only the last year counts unless asked otherwise.
  let mut since = "1 year ago"
  let mut base = None
  let paths = []
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    index += 1
    match arg {
      "--" => {
        paths.push_iter(args[index:].iter())
        break
      }
      "-h" | "--help" => return None
      "--limit" | "--since" | "--base" => {
        guard index < args.length() else { raise Usage("\{arg} needs a value") }
        let value = args[index]
        index += 1
        match arg {
          "--limit" => limit = positive(value)
          "--since" => since = value
          _ => base = Some(value)
        }
      }
      _ if arg.has_prefix("-") => raise Usage("unknown option \{arg}")
      _ => paths.push(arg)
    }
  }
  if base is Some(_) && !paths.is_empty() {
    raise Usage("--base applies only when no path is given")
  }
  Some({ limit, since, base, paths, })
}

///|
fn positive(value : String) -> Int32 raise Usage {
  let number = @string.parse_int(value) catch {
    _ => raise Usage("--limit needs a positive integer")
  }
  guard number > 0 else { raise Usage("--limit needs a positive integer") }
  number
}

///|
priv suberror Failed {
  Failed(String)
}

///|
priv struct Git {
  cwd : String?
}

///|
/// Returns the stdout of a successful command, or `None` when it exits with a nonzero status.
async fn Git::output(self : Git, args : Array[String]) -> String? {
  let (status, stdout, _) = @process.collect_output(
    "git",
    args,
    cwd?=self.cwd.map(cwd => cwd[:]),
  )
  guard status == 0 else { return None }
  Some(@utf8.decode_lossy(stdout.binary()))
}

///|
async fn Git::required(self : Git, args : Array[String]) -> String {
  guard self.output(args) is Some(output) else {
    raise Failed("git \{args.join(" ")} failed")
  }
  output
}

///|
async fn candidates(git : Git, options : Options) -> String {
  let paths = if options.paths.is_empty() {
    changed_files(git, options.base)
  } else {
    options.paths
  }
  let log = git.required(
    [
      "log",
      "--no-merges",
      "--since=\{options.since}",
      "--format=%aN%x09%aE%x09%as",
      "--",
      ..paths,
    ],
  )
  let me = git
    .output(["config", "user.email"])
    .map(email => email.trim().to_owned())
  let ranked = rank(log, me, options.limit)
  guard !ranked.is_empty() else {
    return "no other authors since \{options.since}\n"
  }
  render(ranked)
}

///|
/// The files the current branch changed since it left `base`.
async fn changed_files(git : Git, base : String?) -> Array[String] {
  let base = match base {
    Some(base) => base
    None => default_base(git)
  }
  let files = git
    .required(["diff", "--name-only", "-z", "\{base}...HEAD"])
    .split("\u{0}")
    .filter(file => file != "")
    // `git diff` names files from the top of the repository, while `git log` reads pathspecs from the current directory.
    .map(file => ":(top,literal)\{file}")
    .collect()
  guard !files.is_empty() else {
    raise Failed("no files changed from \{base}; pass the paths to look at")
  }
  files
}

///|
/// The remote's default branch, else the first of `main` and `master` that exists.
async fn default_base(git : Git) -> String {
  if git.output(["rev-parse", "--abbrev-ref", "origin/HEAD"]) is Some(remote) {
    return remote.trim().to_owned()
  }
  for candidate in ["main", "master"] {
    if git.output(["rev-parse", "--verify", "--quiet", candidate]) is Some(_) {
      return candidate
    }
  }
  raise Failed("no default branch found; pass --base")
}

///|
priv struct Author {
  name : String
  email : String
  last : String
  mut commits : Int32
}

///|
/// Counts the commits of each author in `log`, leaving out `me` and bots, most commits first.
fn rank(log : String, me : String?, limit : Int32) -> Array[Author] {
  let me = me.map(email => email.to_lower())
  let authors : Map[String, Author] = Map([])
  for line in log.split("\n") {
    guard line.split("\t").collect() is [name, email, last] else { continue }
    let name = name.to_owned()
    let key = email.to_owned().to_lower()
    if Some(key) == me || name.has_suffix("[bot]") {
      continue
    }
    match authors.get(key) {
      Some(author) => author.commits += 1
      // The log lists the newest commit first, so it gives the name and date shown.
      None =>
        authors[key] = {
          name,
          email: email.to_owned(),
          last: last.to_owned(),
          commits: 1,
        }
    }
  }
  let ranked = []
  for _, author in authors {
    ranked.push(author)
  }
  ranked.sort_by((a, b) => {
    match b.commits.compare(a.commits) {
      0 =>
        match b.last.compare(a.last) {
          0 => a.email.compare(b.email)
          order => order
        }
      order => order
    }
  })
  ranked.iter().take(limit).collect()
}

///|
fn render(authors : Array[Author]) -> String {
  let output = StringBuilder()
  output.write_string("commits  last        author\n")
  for author in authors {
    let commits = author.commits.to_string()
    for _ in commits.length()..<7 {
      output.write_char(' ')
    }
    output.write_string(
      "\{commits}  \{author.last}  \{author.name} <\{author.email}>\n",
    )
  }
  output.to_string()
}
