///|
/// Runs Git in `cwd` without the user's configuration, as `author` at `time`.
async fn git(
  cwd : String,
  args : Array[String],
  author~ : String = "Self",
  time~ : Int32 = 1_700_000_000,
) -> Unit {
  let date = "@\{time} +0000"
  let status = @process.run("git", ["-C", cwd, ..args], extra_env={
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": author,
    "GIT_AUTHOR_EMAIL": "\{author.to_lower()}@example.com",
    "GIT_COMMITTER_NAME": "test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
    "GIT_AUTHOR_DATE": date,
    "GIT_COMMITTER_DATE": date,
  })
  assert_eq(status, 0)
}

///|
/// Numbers every change, so a commit never repeats the content before it.
let changes : Ref[Int32] = Ref(0)

///|
async fn change(
  repository : String,
  path : String,
  author~ : String,
  time~ : Int32 = 1_700_000_000,
) -> Unit {
  changes.val += 1
  @fs.write_file(
    repository + "/" + path,
    "\{changes.val}\n",
    create_mode=CreateOrTruncate,
  )
  git(repository, ["add", path])
  git(repository, ["commit", "-q", "-m", "change"], author~, time~)
}

///|
/// The user's email differs in case from the one Git records, so the match must ignore case.
async fn init_repository(root : String) -> String {
  let repository = root + "/repo"
  @fs.mkdir(repository + "/app", recursive=true)
  @fs.mkdir(repository + "/docs")
  git(repository, ["init", "-q", "-b", "main"])
  git(repository, ["config", "user.email", "SELF@example.com"])
  repository
}

///|
async fn report(cwd : String, args : Array[String]) -> String {
  guard parse_options(args) is Some(options) else { fail("help was parsed") }
  candidates({ cwd: Some(cwd), }, options, Table)
}

///|
async test "authors are ranked by their commits to the paths, without the user and bots" {
  let root = @fs.realpath(@fs.tmpdir(prefix="reviewer-candidates-"))
  let repository = init_repository(root)
  for _ in 0..<3 {
    change(repository, "app/a.txt", author="Alice")
  }
  change(repository, "app/b.txt", author="Bob", time=1_699_000_000)
  change(repository, "app/b.txt", author="Carol")
  change(repository, "app/b.txt", author="Self")
  change(repository, "app/a.txt", author="dependabot[bot]")
  change(repository, "app/a.txt", author="Noreply")
  for _ in 0..<5 {
    change(repository, "docs/c.txt", author="Dave")
  }
  assert_eq(
    report(repository, ["--since", "2023-01-01", "app"]),
    (
      #|commits  last        author
      #|      3  2023-11-14  Alice <alice@example.com>
      #|      1  2023-11-14  Carol <carol@example.com>
      #|      1  2023-11-03  Bob <bob@example.com>
      #|
    ),
  )
  assert_eq(
    report(repository, ["--since", "2023-01-01", "--limit", "1", "app"]),
    (
      #|commits  last        author
      #|      3  2023-11-14  Alice <alice@example.com>
      #|
    ),
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "commits before the start date are left out" {
  let root = @fs.realpath(@fs.tmpdir(prefix="reviewer-candidates-"))
  let repository = init_repository(root)
  change(repository, "app/a.txt", author="Alice", time=1_600_000_000)
  change(repository, "app/a.txt", author="Bob")
  assert_eq(
    report(repository, ["--since", "2023-01-01", "app"]),
    (
      #|commits  last        author
      #|      1  2023-11-14  Bob <bob@example.com>
      #|
    ),
  )
  assert_eq(
    report(repository, ["--since", "2024-01-01", "app"]),
    "no other authors since 2024-01-01\n",
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "without paths, the files the branch changed are looked at from any directory" {
  let root = @fs.realpath(@fs.tmpdir(prefix="reviewer-candidates-"))
  let repository = init_repository(root)
  change(repository, "app/a.txt", author="Alice")
  change(repository, "docs/c.txt", author="Dave")
  git(repository, ["checkout", "-q", "-b", "topic"])
  change(repository, "app/a.txt", author="Self")
  assert_eq(
    report(repository + "/docs", ["--since", "2023-01-01"]),
    (
      #|commits  last        author
      #|      1  2023-11-14  Alice <alice@example.com>
      #|
    ),
  )
  let failure = try report(repository, ["--base", "topic"]) catch {
    Failed(message) => message
    error => raise error
  } noraise {
    _ => "no failure"
  }
  assert_eq(failure, "no files changed from topic; pass the paths to look at")
  @fs.rmdir(root, recursive=true)
}

///|
test "a terminal aligns wide names and scales the bars to the top author" {
  let authors : Array[Author] = [
    {
      name: "Alice",
      email: "alice@example.com",
      last: "2026-11-02",
      ago: "2 weeks ago",
      commits: 4,
    },
    {
      name: "山田",
      email: "yamada@example.com",
      last: "2026-04-28",
      ago: "7 months ago",
      commits: 2,
    },
  ]
  assert_eq(
    view(
      authors,
      "app",
      "since 1 year ago · 3 people",
      Palette::new(color=false),
    ),
    (
      #|app · since 1 year ago · 3 people
      #|
      #|  Alice  ━━━━━━━━━━━━  4 commits  2 weeks ago   alice@example.com
      #|  山田   ━━━━━━──────  2 commits  7 months ago  yamada@example.com
      #|
      #|
    ),
  )
  assert_eq(described(["app", "docs", "e2e"]), "app and 2 more paths")
}

///|
test "a terminal leaves out the bars when every count is the same" {
  let authors : Array[Author] = [
    {
      name: "Alice",
      email: "alice@example.com",
      last: "2026-11-15",
      ago: "1 day ago",
      commits: 1,
    },
    {
      name: "Bob",
      email: "bob@example.com",
      last: "2026-04-28",
      ago: "7 months ago",
      commits: 1,
    },
  ]
  assert_eq(
    view(
      authors,
      "app",
      "since 1 year ago · 2 people",
      Palette::new(color=false),
    ),
    (
      #|app · since 1 year ago · 2 people
      #|
      #|  Alice  1 commit  1 day ago     alice@example.com
      #|  Bob    1 commit  7 months ago  bob@example.com
      #|
      #|
    ),
  )
}

///|
test "options take their values, and paths only without a base" {
  assert_eq(parse_options(["-h"]) is None, true)
  guard parse_options(["--limit", "3", "--", "--odd"]) is Some(options) else {
    fail("no options")
  }
  assert_eq(
    (options.limit, options.since, options.paths),
    (3, "1 year ago", ["--odd"]),
  )
  for
    args in [
      ["--limit"],
      ["--limit", "0"],
      ["--limit", "x"],
      ["--x"],
      ["--base", "main", "app"],
    ] {
    let rejected = try parse_options(args) catch {
      Usage(_) => true
    } noraise {
      _ => false
    }
    assert_eq(rejected, true)
  }
}
