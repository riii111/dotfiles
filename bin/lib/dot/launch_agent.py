"""Manage a resident tool as a per-user LaunchAgent.

review-notifier and the harnexus PR watch run the same way, so how an agent is
written, loaded, stopped and read lives here once.
"""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Agent:
    label: str
    # The dotctl subcommand, named in hints.
    command: str
    home: Path
    binary: Path
    args: tuple[str, ...]
    log: Path
    # Interactive for an agent the owner answers, as notifications are; Background otherwise.
    process_type: str

    @property
    def plist(self) -> Path:
        return self.home / "Library" / "LaunchAgents" / f"{self.label}.plist"

    @property
    def service(self) -> str:
        return f"{domain()}/{self.label}"


def install(agent: Agent, user: str) -> int:
    stop(agent)
    agent.plist.parent.mkdir(parents=True, exist_ok=True)
    agent.log.parent.mkdir(parents=True, exist_ok=True)
    with agent.plist.open("wb") as handle:
        plistlib.dump(agent_plist(agent, user), handle)
    return start(agent)


def uninstall(agent: Agent) -> int:
    status = stop(agent)
    agent.plist.unlink(missing_ok=True)
    return status


def start(agent: Agent) -> int:
    if not agent.plist.exists():
        print(
            f"{agent.plist} not found; run `dotctl {agent.command} install`",
            file=sys.stderr,
        )
        return 1
    if is_loaded(agent):
        return run(["launchctl", "kickstart", "-k", agent.service])
    return run(["launchctl", "bootstrap", domain(), str(agent.plist)])


def stop(agent: Agent) -> int:
    if not is_loaded(agent):
        print(f"{agent.label} is not running")
        return 0
    return run(["launchctl", "bootout", agent.service])


def print_loaded(agent: Agent) -> None:
    print(f"{agent.label}: {'loaded' if is_loaded(agent) else 'not loaded'}")


def logs(agent: Agent, follow: bool) -> int:
    if not agent.log.exists():
        print(f"{agent.log} not found")
        return 1

    args = ["tail", "-n", "200"]
    if follow:
        args.append("-F")
    return run([*args, str(agent.log)])


def agent_plist(agent: Agent, user: str) -> dict:
    home = agent.home
    # launchd starts the agent without the login shell, so PATH is fixed here for
    # gh, git and the helpers they start themselves.
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
        "Label": agent.label,
        "ProgramArguments": [str(agent.binary), *agent.args],
        "EnvironmentVariables": {
            "HOME": str(home),
            "PATH": path,
            "LANG": "en_US.UTF-8",
        },
        "RunAtLoad": True,
        # Restarted after a crash or a config error, but not after a clean stop.
        "KeepAlive": {"SuccessfulExit": False},
        "ThrottleInterval": 60,
        # Notifications, the app's call socket and the gh keychain belong to the logged-in GUI session.
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": agent.process_type,
        "StandardOutPath": str(agent.log),
        "StandardErrorPath": str(agent.log),
    }


def is_loaded(agent: Agent) -> bool:
    return (
        subprocess.run(
            ["launchctl", "print", agent.service],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def domain() -> str:
    return f"gui/{os.getuid()}"


def run(args: list[str], cwd: Path | None = None) -> int:
    print("$", " ".join(args))
    return subprocess.run(args, cwd=cwd, check=False).returncode


# For a check whose full output is long, so only its failure is shown.
def run_quiet(args: list[str]) -> int:
    print("$", " ".join(args))
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode
