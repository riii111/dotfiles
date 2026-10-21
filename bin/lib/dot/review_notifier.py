"""Build tools/review-notifier and manage it as a per-user LaunchAgent."""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path


LABEL = "io.github.riii111.review-notifier"
SOURCE_DIR = Path("tools") / "review-notifier"


def install(repo_root: Path, home: Path, user: str) -> int:
    config = config_path(home)
    if not config.exists():
        print(
            f"{config} not found; copy {repo_root / SOURCE_DIR / 'config.example.json'} and edit it",
            file=sys.stderr,
        )
        return 1
    status = build(repo_root, home)
    if status != 0:
        return status
    # Fails before the agent is loaded if the config, a command or the GitHub API is not usable.
    status = run([str(binary_path(home)), "check"])
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
    binary_path(home).unlink(missing_ok=True)
    print("config, state, logs and review worktrees are kept")
    return status


def start(home: Path) -> int:
    plist = plist_path(home)
    if not plist.exists():
        print(
            f"{plist} not found; run `dotctl review-notifier install`", file=sys.stderr
        )
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
    binary = binary_path(home)
    if not binary.exists():
        print(f"{binary} not found")
        return 1
    return run([str(binary), "status"])


def logs(home: Path, follow: bool) -> int:
    log = log_path(home)
    if not log.exists():
        print(f"{log} not found")
        return 1
    args = ["tail", "-n", "200"]
    if follow:
        args.append("-F")
    return run([*args, str(log)])


def build(repo_root: Path, home: Path) -> int:
    go = shutil.which("go")
    if go is None:
        print("go not found; run `dotctl sync-nix-profile` first", file=sys.stderr)
        return 1
    target = binary_path(home)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f".{target.name}.tmp")
    status = run([go, "build", "-o", str(tmp), "."], repo_root / SOURCE_DIR)
    if status != 0:
        tmp.unlink(missing_ok=True)
        return status
    os.replace(tmp, target)
    return 0


def agent_plist(home: Path, user: str) -> dict:
    # launchd starts the agent without the login shell, so PATH is fixed here for the
    # helpers git and gh start themselves; review-notifier resolves its own commands.
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
        "ProgramArguments": [str(binary_path(home)), "run"],
        "EnvironmentVariables": {
            "HOME": str(home),
            "PATH": path,
            "LANG": "en_US.UTF-8",
        },
        "RunAtLoad": True,
        # Restarted after a crash or a config error, but not after a clean stop.
        "KeepAlive": {"SuccessfulExit": False},
        "ThrottleInterval": 60,
        # Notifications need the logged-in GUI session.
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Interactive",
        "StandardOutPath": str(log_path(home)),
        "StandardErrorPath": str(log_path(home)),
    }


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
    return home / ".local" / "bin" / "review-notifier"


def plist_path(home: Path) -> Path:
    return home / "Library" / "LaunchAgents" / f"{LABEL}.plist"


def log_path(home: Path) -> Path:
    return home / "Library" / "Logs" / "review-notifier.log"


def config_path(home: Path) -> Path:
    return home / ".config" / "review-notifier" / "config.json"


def domain() -> str:
    return f"gui/{os.getuid()}"


def service() -> str:
    return f"{domain()}/{LABEL}"


def run(args: list[str], cwd: Path | None = None) -> int:
    print("$", " ".join(args))
    return subprocess.run(args, cwd=cwd, check=False).returncode
