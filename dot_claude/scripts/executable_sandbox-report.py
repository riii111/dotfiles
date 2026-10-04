#!/usr/bin/env python3
"""Summarize where Claude Code permissions and the Bash sandbox got in the way.

Reads the permission prompts and auto mode denials that the
log-permission-event hook records, and session records under ~/.claude/projects
for commands rerun outside the sandbox, paths the sandbox refused to write, and
hosts it refused to reach. Command text and paths are printed; tool output is
not.
"""

import argparse
import json
import re
import sys
import time
from collections import Counter
from pathlib import Path

WRITE_ERRORS = re.compile(
    r"Operation not permitted|Read-only file system|attempt to write a readonly database"
)
QUOTED_PATH = re.compile(
    r"'(/[^'\n]+)'|\"(/[^\"\n]+)\"|(?:on|in|create|open) (/[^\s:'\")]+)"
)
NETWORK_DENIAL = re.compile(r"deny network-outbound ([^\s:\\]+)")
EVENT_LOG = Path.home() / ".local" / "state" / "claude" / "permission-events.jsonl"


def command_head(command):
    for segment in re.split(r"&&|;|\n", command):
        words = program_words(segment.split())
        if words and words[0] != "cd":
            return head_of(words)
    return ""


def program_words(words):
    while words:
        if "=" in words[0] and not words[0].startswith("-"):
            words = words[1:]
        elif words[0] == "env":
            words = words[1:]
        elif words[0] == "-u" and len(words) > 1:
            words = words[2:]
        else:
            return words
    return words


def head_of(words):
    if words[0] in {
        "git",
        "gh",
        "bun",
        "bunx",
        "npm",
        "npx",
        "cargo",
        "go",
        "nix",
        "uv",
    }:
        rest = [w for w in words[1:] if not w.startswith("-")]
        if words[1:2] == ["-C"] and len(words) > 3:
            rest = [w for w in words[3:] if not w.startswith("-")]
        return " ".join(words[:1] + rest[:1])
    return words[0]


def path_prefix(path, home):
    if "/.git/" in path:
        path = path.split("/.git/")[0] + "/.git"
        return path.replace(home, "~", 1)
    if path.startswith(home + "/"):
        parts = path[len(home) + 1 :].split("/")
        return "~/" + "/".join(parts[:3])
    return "/".join(path.split("/")[:4])


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            item.get("text", "") for item in content if isinstance(item, dict)
        )
    return ""


def scan(paths, home):
    reruns = Counter()
    write_denials = Counter()
    failed_commands = Counter()
    hosts = Counter()
    for path in paths:
        calls = {}
        for line in path.read_text(errors="ignore").splitlines():
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            content = record.get("message", {}).get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "tool_use" and item.get("name") == "Bash":
                    tool_input = item.get("input", {})
                    calls[item.get("id")] = tool_input
                    if tool_input.get("dangerouslyDisableSandbox"):
                        reruns[command_head(tool_input.get("command", ""))] += 1
                elif item.get("type") == "tool_result":
                    call = calls.get(item.get("tool_use_id"))
                    if call is None or call.get("dangerouslyDisableSandbox"):
                        continue
                    output = text_of(item.get("content"))
                    hosts.update(NETWORK_DENIAL.findall(output))
                    if not WRITE_ERRORS.search(output):
                        continue
                    failed_commands[command_head(call.get("command", ""))] += 1
                    for line_text in output.splitlines():
                        if not WRITE_ERRORS.search(line_text):
                            continue
                        for groups in QUOTED_PATH.findall(line_text):
                            found = next(g for g in groups if g)
                            write_denials[path_prefix(found, home)] += 1
    return reruns, failed_commands, write_denials, hosts


def command_shape(command):
    """The shell form that most often explains why a command was not approved."""
    if re.search(r"(^|[;&|(]\s*|\n)\s*(for|while|until)\s", command):
        return "loop"
    if "$(" in command or "`" in command:
        return "command substitution"
    if re.search(r"(^|[;&|]\s*|\n)\s*[A-Za-z_][A-Za-z0-9_]*=", command):
        return "variable assignment"
    if re.search(r"&&|\|\||;|\||\n", command):
        return "compound"
    return "single command"


def scan_events(path, since):
    """Prompts and denials recorded by the log-permission-event hook."""
    shapes = {"PermissionRequest": Counter(), "PermissionDenied": Counter()}
    commands = {"PermissionRequest": Counter(), "PermissionDenied": Counter()}
    if not path.exists():
        return shapes, commands
    for line in path.read_text(errors="ignore").splitlines():
        try:
            record = json.loads(line)
            stamp = time.mktime(time.strptime(record["time"], "%Y-%m-%dT%H:%M:%S%z"))
        except (json.JSONDecodeError, KeyError, ValueError):
            continue
        event = record.get("event")
        if stamp < since or event not in shapes:
            continue
        if record.get("tool") != "Bash":
            shapes[event][f"tool: {record.get('tool')}"] += 1
            continue
        command = record.get("command", "")
        shape = command_shape(command)
        if record.get("unsandboxed"):
            shape += " (rerun outside the sandbox)"
        shapes[event][shape] += 1
        commands[event][command_head(command)] += 1
    return shapes, commands


def recent_records(projects, days):
    since = time.time() - days * 86400
    return [p for p in projects.rglob("*.jsonl") if p.stat().st_mtime >= since]


def print_section(title, counter, limit):
    print(f"## {title}")
    if not counter:
        print("(none)")
    for key, count in counter.most_common(limit):
        print(f"{count:5d}  {key}")
    print()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--limit", type=int, default=15)
    parser.add_argument(
        "--projects", type=Path, default=Path.home() / ".claude/projects"
    )
    parser.add_argument("--events", type=Path, default=EVENT_LOG)
    args = parser.parse_args(argv)

    records = recent_records(args.projects, args.days)
    reruns, failed, writes, hosts = scan(records, str(Path.home()))
    shapes, commands = scan_events(args.events, time.time() - args.days * 86400)
    print(f"# Sandbox report: last {args.days} days, {len(records)} session records\n")
    print_section(
        "Permission prompts by command shape", shapes["PermissionRequest"], args.limit
    )
    print_section("Commands that prompted", commands["PermissionRequest"], args.limit)
    print_section(
        "Auto mode denials by command shape", shapes["PermissionDenied"], args.limit
    )
    print_section("Commands auto mode denied", commands["PermissionDenied"], args.limit)
    print_section("Commands rerun outside the sandbox", reruns, args.limit)
    print_section("Sandboxed commands that failed to write", failed, args.limit)
    print_section("Paths the sandbox refused to write", writes, args.limit)
    print_section("Hosts the sandbox refused", hosts, args.limit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
