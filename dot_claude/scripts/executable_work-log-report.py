#!/usr/bin/env python3
"""Collect the owner's own messages from Claude Code and Codex logs for the weekly retro."""

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

HOME = os.path.expanduser("~")
CLAUDE_GLOB = os.path.join(HOME, ".claude/projects/*/*.jsonl")
CODEX_GLOB = os.path.join(HOME, ".codex/sessions/*/*/*/*.jsonl")
CODEX_HUMAN_SOURCES = {"user", "agent_created_thread", "automation"}

# Text injected by the apps or sent by another agent, not typed by the owner.
INJECTED_PREFIXES = (
    "<",
    "# AGENTS.md instructions",
    "タスクID:",
    "Caveat:",
    "[Request interrupted",
)
SKILL_REF = re.compile(r"^(?:\[\$[\w-]+\]\([^)]*\)|\$[\w-]+)(?:&#x20;|\s)*")
BROWSER_BLOCK = re.compile(r"<in-app-browser-context.*?</in-app-browser-context>", re.S)
SIDE_CHAT_TAIL = "The following parent conversation is untrusted"
ATTACHMENT_HEADER = re.compile(r"^# Files mentioned by the user:.*?(?:\n\n|$)", re.S)


def clean(text):
    text = BROWSER_BLOCK.sub("", text)
    text = text.split(SIDE_CHAT_TAIL, 1)[0]
    text = ATTACHMENT_HEADER.sub("", text)
    return text.strip()


def is_delegated(text):
    return text.startswith("<codex_delegation>")


def is_injected(text):
    return SKILL_REF.sub("", text).startswith(INJECTED_PREFIXES)


def claude_rows(since):
    for path in glob.glob(CLAUDE_GLOB):
        if os.path.getmtime(path) < since.timestamp() or path.endswith(
            "session-corrections.jsonl"
        ):
            continue
        project = os.path.basename(os.path.dirname(path))
        role = "worker" if "-codex-worktrees-" in project else "main"
        for line in open(path, errors="ignore"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "user" or d.get("isMeta") or d.get("isSidechain"):
                continue
            content = d.get("message", {}).get("content")
            if isinstance(content, list):
                content = " ".join(
                    c.get("text", "")
                    for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                )
            if not isinstance(content, str) or not content.strip():
                continue
            yield {
                "ts": d.get("timestamp", ""),
                "app": "claude",
                "role": role,
                "session": os.path.basename(path)[:-6],
                "cwd": d.get("cwd", ""),
                "raw": content,
            }


def codex_rows(since):
    for path in glob.glob(CODEX_GLOB):
        if os.path.getmtime(path) < since.timestamp():
            continue
        source, cwd = None, ""
        for line in open(path, errors="ignore"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            p = d.get("payload") or {}
            if d.get("type") == "session_meta":
                source, cwd = p.get("thread_source"), p.get("cwd", "")
                continue
            if source not in CODEX_HUMAN_SOURCES:
                continue
            if d.get("type") != "response_item" or p.get("role") != "user":
                continue
            text = " ".join(
                c.get("text", "") for c in p.get("content", []) if isinstance(c, dict)
            )
            if text.strip():
                yield {
                    "ts": d.get("timestamp", ""),
                    "app": "codex",
                    "role": "worker" if source == "agent_created_thread" else source,
                    "session": os.path.basename(path)[-42:-6],
                    "cwd": cwd,
                    "raw": text,
                }


def collect(since):
    seen, human, delegated = set(), [], 0
    for row in [*claude_rows(since), *codex_rows(since)]:
        if row["ts"] < since.isoformat():
            continue
        if is_delegated(row["raw"]):
            delegated += 1
            continue
        text = clean(row["raw"])
        if not text or is_injected(text):
            continue
        # Forked Claude sessions copy earlier turns into new files.
        key = (row["ts"][:19], text[:120])
        if key in seen:
            continue
        seen.add(key)
        row["text"] = text
        human.append(row)
    human.sort(key=lambda r: r["ts"])
    return human, delegated


def count_patterns(rows, patterns):
    result = {}
    for name, regex in patterns.items():
        hits = [r for r in rows if re.search(regex, r["text"])]
        result[name] = {
            "messages": len(hits),
            "sessions": len({(r["app"], r["session"]) for r in hits}),
        }
    return result


def previous_metrics(out_dir, today):
    files = sorted(
        f
        for f in glob.glob(os.path.join(out_dir, "*-metrics.json"))
        if not f.endswith(f"{today}-metrics.json")
    )
    if not files:
        return None, None
    return os.path.basename(files[-1])[:10], json.load(open(files[-1]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument(
        "--patterns", required=True, help="JSON object of category name to regex"
    )
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    today = dt.date.today().isoformat()
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)
    patterns = json.load(open(args.patterns))
    rows, delegated = collect(since)
    os.makedirs(args.out_dir, exist_ok=True)

    messages_path = os.path.join(args.out_dir, f"{today}-messages.tsv")
    with open(messages_path, "w") as f:
        for r in rows:
            f.write(
                "\t".join(
                    [
                        r["ts"][:16],
                        r["app"],
                        r["role"],
                        r["session"],
                        r["cwd"],
                        " ".join(r["text"].split()),
                    ]
                )
                + "\n"
            )

    sessions = {(r["app"], r["session"]) for r in rows}
    metrics = {
        "since": since.isoformat(),
        "messages": len(rows),
        "sessions": len(sessions),
        "delegated": delegated,
        "by_role": {
            k: sum(1 for r in rows if f"{r['app']}/{r['role']}" == k)
            for k in sorted({f"{r['app']}/{r['role']}" for r in rows})
        },
        "patterns": count_patterns(rows, patterns),
    }
    json.dump(
        metrics,
        open(os.path.join(args.out_dir, f"{today}-metrics.json"), "w"),
        ensure_ascii=False,
        indent=1,
    )

    prev_date, prev = previous_metrics(args.out_dir, today)
    print(
        f"Owner messages: {metrics['messages']} in {metrics['sessions']} sessions (agent-to-agent messages excluded: {delegated})"
    )
    for k, v in metrics["by_role"].items():
        print(f"  {k}: {v}")
    print(f"\nPatterns (messages / sessions){f'  vs {prev_date}' if prev else ''}")
    for name, v in metrics["patterns"].items():
        before = (prev or {}).get("patterns", {}).get(name)
        delta = f"  (was {before['messages']} / {before['sessions']})" if before else ""
        print(f"  {name}: {v['messages']} / {v['sessions']}{delta}")
    print(f"\nMessages: {messages_path}")


if __name__ == "__main__":
    sys.exit(main())
