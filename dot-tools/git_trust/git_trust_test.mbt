///|
/// The parsed remote as `scheme:host/owner/repo`, where SSH covers both `git@` and `ssh://` remotes.
fn parsed(url : String) -> String? {
  @git_trust.parse_remote(url).map(remote => {
    let host = match remote.host {
      Https(host) => "https:" + host
      Ssh(host) => "ssh:" + host
    }
    "\{host}/\{remote.owner}/\{remote.repo}"
  })
}

///|
test "remotes give their host and the lowercased owner and repository" {
  let cases = [
    ("git@github.com:Riii111/Test.git", "ssh:github.com/riii111/test"),
    ("git@github.com:a/b", "ssh:github.com/a/b"),
    ("git@work-github:a/b.git", "ssh:work-github/a/b"),
    ("git@github.com:a/b.git.git", "ssh:github.com/a/b.git"),
    ("git@example.com:a/b", "ssh:example.com/a/b"),
    // An empty host parses, and `github_host` rejects it.
    ("git@:a/b", "ssh:/a/b"),
    ("ssh://[github.com]/a/b", "ssh:/a/b"),
    ("ssh:///a/b", "ssh:/a/b"),
    ("https://github.com/A/B.git", "https:github.com/a/b"),
    ("https://GitHub.com/a/b", "https:github.com/a/b"),
    ("HTTPS://github.com/a/b", "https:github.com/a/b"),
    ("https://user@github.com:8443/a/b", "https:github.com/a/b"),
    ("https://github.com/a/b?", "https:github.com/a/b"),
    ("https://git\thub.com/a/b", "https:github.com/a/b"),
    ("https://work-github/a/b", "https:work-github/a/b"),
    ("ssh://git@github.com/a/b.git", "ssh:github.com/a/b"),
    ("ssh://git@work-github:22/a/b", "ssh:work-github/a/b"),
    ("ssh://git@github.com/a/b.git?", "ssh:github.com/a/b"),
    ("ssh://example.com/a/b", "ssh:example.com/a/b"),
  ]
  for case in cases {
    let (url, expected) = case
    assert_eq(parsed(url), Some(expected), msg=url)
  }
}

///|
test "malformed remotes and other schemes are rejected" {
  let urls = [
    "git@github.com:/a/b", "git@github.com:a/b/c", "git@github.com:a/", "https://github.com/a/b?x=1",
    "https://github.com/a/b#f", "https://github.com/a/b/", "https://github.com//a/b",
    "https://github.com/a/b.git/", "https:github.com/a/b", "http://github.com/a/b",
    "file:///a/b", "github.com:a/b",
  ]
  for url in urls {
    assert_eq(parsed(url), None, msg=url)
  }
}

///|
test "only GitHub's SSH endpoints count as GitHub" {
  let cases = [
    ("github.com", "22", true),
    ("ssh.github.com", "443", true),
    ("github.com", "443", false),
    ("example.com", "22", false),
  ]
  for case in cases {
    let (host, port, expected) = case
    assert_eq(
      @git_trust.is_github_endpoint(
        "user git\nhostname \{host}\nport \{port}\n",
      ),
      expected,
    )
  }
  assert_eq(@git_trust.is_github_endpoint("hostname github.com\n"), true)
  assert_eq(@git_trust.is_github_endpoint("port 22\n"), false)
}

///|
test "relative_parts accepts only paths below the base" {
  assert_eq(
    @git_trust.relative_parts(
      "/home/u/ghq/github.com/a/b", "/home/u/ghq/github.com",
    ),
    Some(["a", "b"]),
  )
  assert_eq(
    @git_trust.relative_parts(
      "/home/u/ghq/github.com-x/a/b", "/home/u/ghq/github.com",
    ),
    None,
  )
  assert_eq(
    @git_trust.relative_parts(
      "/home/u/ghq/github.com", "/home/u/ghq/github.com",
    ),
    None,
  )
}

///|
async fn git(cwd : String, args : Array[String]) -> Unit {
  let status = @process.run("git", ["-C", cwd, ..args])
  assert_eq(status, 0)
}

///|
/// Creates `HOME/ghq/github.com/riii111/test` with an origin on GitHub and returns `(home, repository)`.
async fn trusted_checkout() -> (String, String) {
  let home = @fs.realpath(@fs.tmpdir(prefix="git-trust-"))
  let repository = home + "/ghq/github.com/riii111/test"
  @fs.mkdir(repository, recursive=true)
  git(repository, ["init", "-q"])
  git(repository, [
    "remote", "add", "origin", "https://github.com/riii111/test.git",
  ])
  (home, repository)
}

///|
async test "a ghq checkout with a matching GitHub origin is trusted" {
  let (home, repository) = trusted_checkout()
  @fs.mkdir(repository + "/sub")
  assert_eq(
    @git_trust.trusted_repository(repository + "/sub", home~),
    Some(repository),
  )
  @fs.rmdir(home, recursive=true)
}

///|
async test "untrusted origins and checkouts outside ghq are rejected" {
  let changes = [
    ["remote", "set-url", "origin", "https://work-github/riii111/test.git"],
    ["remote", "set-url", "origin", "https://example.com/riii111/test.git"],
    ["remote", "set-url", "origin", "https://github.com/riii111/other.git"],
    [
      "config", "url.file:///tmp/remote.git.insteadOf", "https://github.com/riii111/test.git",
    ],
    [
      "config", "url.file:///tmp/remote.git.pushInsteadOf", "https://github.com/riii111/test.git",
    ],
    ["config", "--add", "remote.origin.url", "https://github.com/a/b.git"],
    ["config", "--add", "remote.origin.pushurl", "https://github.com/a/b.git"],
    ["remote", "remove", "origin"],
  ]
  for change in changes {
    let (home, repository) = trusted_checkout()
    git(repository, change)
    assert_eq(@git_trust.trusted_repository(repository, home~), None)
    @fs.rmdir(home, recursive=true)
  }

  let (home, repository) = trusted_checkout()
  assert_eq(@git_trust.trusted_repository(repository, home=home + "/ghq"), None)
  @fs.rmdir(home, recursive=true)
}
