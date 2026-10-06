import os
import subprocess
from pathlib import Path
from urllib.parse import urlparse


GITHUB_SSH_ENDPOINTS = {("github.com", "22"), ("ssh.github.com", "443")}


def git_environment() -> dict[str, str]:
    environment = dict(os.environ)
    for name in list(environment):
        if name.startswith("GIT_"):
            del environment[name]
    return environment


def run_git(cwd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        env=git_environment(),
        check=False,
        capture_output=True,
        text=True,
    )


def repository_root(cwd: Path) -> Path | None:
    result = run_git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if result.returncode != 0:
        return None
    common_dir = Path(result.stdout.strip()).resolve()
    if common_dir.name != ".git":
        return None
    root = common_dir.parent
    trusted_root = (Path.home() / "ghq" / "github.com").resolve()
    try:
        relative = root.relative_to(trusted_root)
    except ValueError:
        return None
    if len(relative.parts) != 2:
        return None
    return root


def github_host(host: str | None) -> bool:
    if not host:
        return False
    try:
        result = subprocess.run(
            ["ssh", "-G", host],
            env=git_environment(),
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if result.returncode != 0:
        return False
    settings = dict(
        line.split(maxsplit=1)
        for line in result.stdout.splitlines()
        if len(line.split(maxsplit=1)) == 2
    )
    return (
        settings.get("hostname"),
        settings.get("port", "22"),
    ) in GITHUB_SSH_ENDPOINTS


def github_repository(url: str) -> tuple[str, str] | None:
    if url.startswith("git@") and ":" in url:
        user_host, path = url[4:].split(":", 1)
        if github_host(user_host):
            parts = path.removesuffix(".git").split("/")
            if len(parts) == 2 and all(parts):
                return parts[0].lower(), parts[1].lower()
        return None
    parsed = urlparse(url)
    if parsed.scheme == "https":
        valid_host = parsed.hostname == "github.com"
    elif parsed.scheme == "ssh":
        valid_host = github_host(parsed.hostname)
    else:
        valid_host = False
    if not valid_host:
        return None
    parts = parsed.path.removeprefix("/").removesuffix(".git").split("/")
    if len(parts) != 2 or not all(parts) or parsed.query or parsed.fragment:
        return None
    return parts[0].lower(), parts[1].lower()


def trusted_repository(cwd: Path) -> Path | None:
    root = repository_root(cwd)
    if root is None:
        return None
    expected = tuple(
        root.relative_to((Path.home() / "ghq" / "github.com").resolve()).parts
    )
    if len(expected) != 2:
        return None
    for push in (False, True):
        args = ["remote", "get-url"]
        if push:
            args.append("--push")
        args.extend(["--all", "origin"])
        result = run_git(cwd, *args)
        if result.returncode != 0:
            return None
        urls = [line for line in result.stdout.splitlines() if line]
        if not urls or any(github_repository(url) != expected for url in urls):
            return None
    return root
