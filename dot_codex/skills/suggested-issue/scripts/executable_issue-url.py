#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote, urlencode

# GitHub does not document a hard limit; past this the 414 risk is real enough to shorten first.
DEFAULT_MAX_LENGTH = 8000

REMOTE_PATTERNS = (
    re.compile(r"^https://(?:[^@/]+@)?github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$"),
    re.compile(r"^ssh://git@github\.com(?::\d+)?/([^/]+)/([^/]+?)(?:\.git)?/?$"),
    re.compile(r"^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?/?$"),
)
REPO_PATTERN = re.compile(r"^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$")


class UsageError(Exception):
    pass


def parse_remote(url):
    for pattern in REMOTE_PATTERNS:
        match = pattern.match(url.strip())
        if match:
            return f"{match.group(1)}/{match.group(2)}"
    return None


def git_remote_repos(cwd):
    names = subprocess.run(
        ["git", "remote"], cwd=cwd, capture_output=True, text=True, check=True
    ).stdout.split()
    repos = {}
    for name in names:
        url = subprocess.run(
            ["git", "remote", "get-url", name],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        repo = parse_remote(url)
        if repo:
            repos.setdefault(repo, []).append(name)
    return repos


def resolve_repo(explicit, cwd):
    if explicit:
        if not REPO_PATTERN.match(explicit):
            raise UsageError(f"invalid repository: {explicit} (expected OWNER/REPO)")
        return explicit
    try:
        repos = git_remote_repos(cwd)
    except (OSError, subprocess.CalledProcessError):
        raise UsageError("not a git repository; pass --repo OWNER/REPO")
    if not repos:
        raise UsageError("no GitHub remote found; pass --repo OWNER/REPO")
    if len(repos) > 1:
        candidates = ", ".join(
            f"{repo} ({'/'.join(names)})" for repo, names in sorted(repos.items())
        )
        raise UsageError(f"multiple GitHub remotes: {candidates}; pass --repo")
    return next(iter(repos))


def build_url(repo, title, body):
    query = urlencode({"title": title, "body": body}, quote_via=quote)
    return f"https://github.com/{repo}/issues/new?{query}"


def read_body(path):
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text(encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build a prefilled GitHub new-issue URL without posting it."
    )
    parser.add_argument("--title", required=True)
    parser.add_argument("--body-file", required=True, help="path, or - for stdin")
    parser.add_argument("--repo", help="OWNER/REPO; defaults to the git remote")
    parser.add_argument("--max-length", type=int, default=DEFAULT_MAX_LENGTH)
    args = parser.parse_args(argv)

    try:
        repo = resolve_repo(args.repo, Path.cwd())
    except UsageError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    title = args.title.strip()
    if not title:
        print("error: title is empty", file=sys.stderr)
        return 2

    url = build_url(repo, title, read_body(args.body_file))
    too_long = len(url) > args.max_length
    print(
        json.dumps(
            {
                "repo": repo,
                "length": len(url),
                "max_length": args.max_length,
                "too_long": too_long,
                # Withheld when too long so a link that may 414 is never handed out.
                "url": None if too_long else url,
            },
            ensure_ascii=False,
        )
    )
    return 3 if too_long else 0


if __name__ == "__main__":
    sys.exit(main())
