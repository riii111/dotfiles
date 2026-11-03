// The parsing follows Python's urllib.parse.urlsplit, which the earlier Python check used, so the same remotes stay trusted.

///|
/// How a remote reaches its host: an `https` remote must name github.com itself, while an SSH alias is checked through `ssh -G`.
pub(all) enum RemoteHost {
  Https(String)
  Ssh(String)
}

///|
/// A remote URL split into its host and its lowercased owner and repository.
pub(all) struct Remote {
  host : RemoteHost
  owner : String
  repo : String
}

///|
/// Parses `git@HOST:OWNER/REPO`, `https://HOST/OWNER/REPO` and `ssh://HOST/OWNER/REPO`, with an optional `.git`.
pub fn parse_remote(url : String) -> Remote? {
  if url.strip_prefix("git@") is Some(rest) && rest.contains(":") {
    guard rest.to_owned().split_once(":") is Some((host, path)) else {
      return None
    }
    return owner_and_repo(path.to_owned(), Ssh(host.to_owned()))
  }

  guard split_url(url) is Some(parts) else { return None }
  let host = match parts.scheme {
    "https" => Https(parts.hostname.unwrap_or(""))
    "ssh" => Ssh(parts.hostname.unwrap_or(""))
    _ => return None
  }
  guard parts.query == "" && parts.fragment == "" else { return None }
  owner_and_repo(
    parts.path
    .strip_prefix("/")
    .map(view => view.to_owned())
    .unwrap_or(parts.path),
    host,
  )
}

///|
fn owner_and_repo(path : String, host : RemoteHost) -> Remote? {
  let path = path
    .strip_suffix(".git")
    .map(view => view.to_owned())
    .unwrap_or(path)
  let parts = path.split("/").collect()
  guard parts is [owner, repo] && owner != "" && repo != "" else { None }
  Some({
    host,
    owner: owner.to_owned().to_lower(),
    repo: repo.to_owned().to_lower(),
  })
}

///|
priv struct UrlParts {
  scheme : String
  hostname : String?
  path : String
  query : String
  fragment : String
}

///|
fn split_url(raw : String) -> UrlParts? {
  let url = StringBuilder()
  for char in raw.trim_start(chars=c0_control_or_space) {
    if char != '\t' && char != '\r' && char != '\n' {
      url.write_char(char)
    }
  }
  let url = url.to_string()

  guard url.split_once(":") is Some((scheme, rest)) &&
    is_scheme(scheme.to_owned()) else {
    return None
  }
  guard rest.strip_prefix("//") is Some(rest) else {
    return Some({
      scheme: scheme.to_owned().to_lower(),
      hostname: None,
      path: "",
      query: "",
      fragment: "",
    })
  }
  let rest = rest.to_owned()
  let netloc_end = rest.find_by(char => {
    char == '/' || char == '?' || char == '#'
  })
  let (netloc, rest) = match netloc_end {
    Some(index) => (rest[:index].to_owned(), rest[index:].to_owned())
    None => (rest, "")
  }
  let (rest, fragment) = match rest.split_once("#") {
    Some((before, after)) => (before.to_owned(), after.to_owned())
    None => (rest, "")
  }
  let (path, query) = match rest.split_once("?") {
    Some((before, after)) => (before.to_owned(), after.to_owned())
    None => (rest, "")
  }
  Some({
    scheme: scheme.to_owned().to_lower(),
    hostname: hostname(netloc),
    path,
    query,
    fragment,
  })
}

///|
let c0_control_or_space : String = {
  let chars = StringBuilder()
  for code in 0..<=0x20 {
    chars.write_char(code.unsafe_to_char())
  }
  chars.to_string()
}

///|
fn is_scheme(scheme : String) -> Bool {
  guard scheme.get_char(0) is Some(first) && first.is_ascii_alphabetic() else {
    return false
  }
  scheme
  .iter()
  .all(char => {
    char.is_ascii_alphabetic() ||
    char.is_ascii_digit() ||
    char == '+' ||
    char == '-' ||
    char == '.'
  })
}

///|
fn hostname(netloc : String) -> String? {
  let hostinfo = match netloc.rev_split_once("@") {
    Some((_, after)) => after.to_owned()
    None => netloc
  }
  // urlsplit rejects a bracketed host unless it is an IP address, and GitHub is never reached by one.
  guard !hostinfo.contains("[") else { return None }
  let name = match hostinfo.split_once(":") {
    Some((name, _)) => name.to_owned()
    None => hostinfo
  }
  if name == "" {
    None
  } else {
    Some(name.to_lower())
  }
}

///|
let github_ssh_endpoints : Array[(String, String)] = [
  ("github.com", "22"),
  ("ssh.github.com", "443"),
]

///|
/// Tells whether `ssh -G` output resolves to GitHub's SSH endpoint.
pub fn is_github_endpoint(ssh_config : String) -> Bool {
  let mut hostname = None
  let mut port = "22"
  for line in ssh_config.split("\n") {
    guard split_setting(line.to_owned()) is Some((key, value)) else { continue }
    match key {
      "hostname" => hostname = Some(value)
      "port" => port = value
      _ => ()
    }
  }
  hostname is Some(hostname) && github_ssh_endpoints.contains((hostname, port))
}

///|
fn split_setting(line : String) -> (String, String)? {
  let line = skip_whitespace(line)
  guard line.find_by(@shell.is_python_whitespace) is Some(index) else {
    return None
  }
  let value = skip_whitespace(line[index:].to_owned())
  guard value != "" else { None }
  Some((line[:index].to_owned(), value))
}

///|
fn skip_whitespace(text : String) -> String {
  match text.find_by(char => !@shell.is_python_whitespace(char)) {
    Some(index) => text[index:].to_owned()
    None => ""
  }
}
