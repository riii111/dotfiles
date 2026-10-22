"""Run `harnexus-task watch` as a per-user LaunchAgent.

The watch tells each task worker what happened on its PR. It is kept apart from
review-notifier, which notifies the owner, so either can be stopped alone.
"""

from __future__ import annotations

import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path


LABEL = "io.github.riii111.pr-watch"


def install(home: Path, user: str) -> int:
    for path, hint in (
        (config_path(home), "apply it with chezmoi"),
        (binary_path(home), "run `bun run install:task` in the harnexus checkout"),
    ):
        if not path.exists():
            print(f"{path} not found; {hint}", file=sys.stderr)
            return 1
    # Fails before the agent is loaded if the config, a gh account or the GitHub API is not usable.
    status = run_quiet([str(binary_path(home)), "watch", "--dry-run"])
    if status != 0:
        return status

    stop()
    plist = plist_path(home)
    plist.parent.mkdir(parents=True, exist_ok=True)
    log_path(home).parent.mkdir(parents=True, exist_ok=True)
    with plist.open("wb") as handle:
        plistlib.dump(agent_plist(home, user), handle)
    return start(home)


def uninstall(home: Path) -> int:
    status = stop()
    plist_path(home).unlink(missing_ok=True)
    print("config, state and logs are kept")
    return status


def start(home: Path) -> int:
    plist = plist_path(home)
    if not plist.exists():
        print(f"{plist} not found; run `dotctl pr-watch install`", file=sys.stderr)
        return 1
    if is_loaded():
        return run(["launchctl", "kickstart", "-k", service()])
    return run(["launchctl", "bootstrap", domain(), str(plist)])


def stop() -> int:
    if not is_loaded():
        print(f"{LABEL} is not running")
        return 0
    return run(["launchctl", "bootout", service()])


def status(home: Path) -> int:
    print(f"{LABEL}: {'loaded' if is_loaded() else 'not loaded'}")
    for line in watched_prs(state_root(home)):
        print(line)
    return 0


def logs(home: Path, follow: bool) -> int:
    log = log_path(home)
    if not log.exists():
        print(f"{log} not found")
        return 1

    args = ["tail", "-n", "200"]
    if follow:
        args.append("-F")
    return run([*args, str(log)])


def agent_plist(home: Path, user: str) -> dict:
    # launchd starts the agent without the login shell, so PATH is fixed here for
    # the gh that reads each account's token.
    path = ":".join(
        [
            str(home / ".nix-profile" / "bin"),
            f"/etc/profiles/per-user/{user}/bin",
            "/run/current-system/sw/bin",
            "/nix/var/nix/profiles/default/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    )
    return {
        "Label": LABEL,
        "ProgramArguments": [str(binary_path(home)), "watch"],
        "EnvironmentVariables": {
            "HOME": str(home),
            "PATH": path,
            "LANG": "en_US.UTF-8",
        },
        "RunAtLoad": True,
        # Restarted after a crash, but not after a clean stop.
        "KeepAlive": {"SuccessfulExit": False},
        "ThrottleInterval": 60,
        # The app's call socket and the gh keychain belong to the logged-in GUI session.
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Background",
        "StandardOutPath": str(log_path(home)),
        "StandardErrorPath": str(log_path(home)),
    }


def watched_prs(root: Path) -> list[str]:
    lines = []
    for link_file in sorted(root.glob("*/link.json")):
        link = read_json(link_file)
        state = read_json(link_file.with_name("state.json"))
        if link is None:
            continue
        status = state.get("status", "watching") if state else "watching"
        reason = state.get("reason") if state else None
        pending = len(state.get("pending", [])) if state else 0
        detail = f" ({reason})" if reason else ""
        lines.append(f"{link.get('url')} {status}{detail} pending={pending}")
    return lines


def read_json(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def is_loaded() -> bool:
    return (
        subprocess.run(
            ["launchctl", "print", service()],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def binary_path(home: Path) -> Path:
    return home / ".local" / "bin" / "harnexus-task"


def config_path(home: Path) -> Path:
    return home / ".config" / "harnexus" / "pr-watch.json"


def state_root(home: Path) -> Path:
    return home / ".local" / "state" / "taskctl" / "watch"


def plist_path(home: Path) -> Path:
    return home / "Library" / "LaunchAgents" / f"{LABEL}.plist"


def log_path(home: Path) -> Path:
    return home / "Library" / "Logs" / "pr-watch.log"


def domain() -> str:
    return f"gui/{os.getuid()}"


def service() -> str:
    return f"{domain()}/{LABEL}"


def run(args: list[str]) -> int:
    print("$", " ".join(args))
    return subprocess.run(args, check=False).returncode


# The dry run lists every comment of every open PR, so only its failure is shown.
def run_quiet(args: list[str]) -> int:
    print("$", " ".join(args))
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode
