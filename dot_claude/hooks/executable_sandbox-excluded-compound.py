#!/usr/bin/python3 -I
"""Deny Bash commands that join a sandbox-excluded program with other code.

Claude Code runs a whole command outside the sandbox when it matches
sandbox.excludedCommands, so `git status; cp x ~/.local/bin/y` would run the
`cp` unsandboxed without a prompt. Errors and bad input fail closed.
"""

import json
import os
import re
import shlex
import sys
from pathlib import Path

HEREDOC = re.compile(r"\$\(cat <<'([A-Za-z_]\w*)'\n")
REDIRECTS = re.compile(r"(?<!\S)(2>&1|2?>/dev/null)(?!\S)")
CD = re.compile(r"cd [\w./~+@-]+")
# Filters allowed after one final pipe: (flag pattern, flags taking a value,
# maximum positional arguments). Files as arguments are not allowed.
FILTERS = {
    "head": (r"-[nc]?[0-9]+", {"-n", "-c"}, 0),
    "tail": (r"-[nc]?[0-9]+", {"-n", "-c"}, 0),
    "wc": (r"-[lcwm]+", set(), 0),
    "jq": (r"-[rcejSM]+|--(raw|compact)-output", set(), 1),
    "rg": (
        r"-[inwvFcoxS]+|--(ignore-case|fixed-strings|count|invert-match)",
        {"-e"},
        1,
    ),
    "sort": (r"-[rnuhfbV]+", set(), 0),
    "uniq": (r"-[cdiu]+", set(), 0),
    "cut": (r"-[df].+|-[cb][0-9,-]+", {"-d", "-f", "-c", "-b"}, 0),
    "tr": (r"-[dsc]+", set(), 2),
}
REASON = (
    "{} is excluded from the sandbox, so this whole command would run unsandboxed. "
    "Run it alone, without ;, &, |, <, >, (, ), $, backticks or newlines. Allowed: "
    "2>&1, >/dev/null, a leading `cd <path> &&`, chains of excluded commands, and "
    "one final pipe into head, tail, wc, jq, rg, sort, uniq, cut or tr."
)


def parse_patterns(patterns):
    """Map each excluded program to its literal words; None means every command."""
    names = {}
    for words in (pattern.replace(":*", " *").split() for pattern in patterns):
        if not words or "*" in words[0]:
            return None
        literal = []
        for word in words[1:]:
            if "*" in word:
                break
            literal.append(word)
        names.setdefault(words[0].rsplit("/", 1)[-1], []).append(literal)
    return names


def excluded(words, names):
    while words and (
        words[0] in ("!", "{", "(") or re.match(r"[A-Za-z_]\w*=", words[0])
    ):
        words = words[1:]
    if not words:
        return None
    name = words[0].lstrip("(").rsplit("/", 1)[-1]
    if names is None or any(
        words[1 : len(lit) + 1] == lit for lit in names.get(name, [])
    ):
        return name
    return None


def safe_filter(words):
    flags, valued, positional = FILTERS.get(words[0], (None, set(), 0))
    rest = iter(words[1:])
    for word in rest:
        if word in valued:
            next(rest, None)
        elif word.startswith("-") and (flags is None or not re.fullmatch(flags, word)):
            return False
        elif not word.startswith("-"):
            positional -= 1
    return flags is not None and positional >= 0


def split(command):
    """Split at ;, &&, || and | outside quotes; return (segments, bad)."""
    segments, separators, start, quote, bad, i = [], [], 0, None, False, 0
    while i < len(command):
        char, pair = command[i], command[i : i + 2]
        if quote != "'" and char == "\\":
            i += 1
        elif char in "'\"" and quote in (None, char):
            quote = None if quote else char
        elif quote != "'" and char in "$`":
            bad = True
        elif quote is None and (pair in ("&&", "||") or char in ";|"):
            segments.append(command[start:i])
            separators.append(pair if pair in ("&&", "||") else char)
            i += len(separators[-1]) - 1
            start = i + 1
        elif quote is None and char in "&<>()\n":
            bad = True
        i += 1
    return segments + [command[start:]], separators, bad or quote is not None


def strip_commit_heredocs(command):
    """Replace `$(cat <<'EOF' ... EOF\n)` whose body ends at the first EOF line."""
    out, position = [], 0
    while match := HEREDOC.search(command, position):
        closing = f"\n{match.group(1)}\n)"
        end = command.find(closing[:-1], match.end() - 1)
        if end == -1 or not command.startswith(closing, end):
            break
        out.append(command[position : match.start()] + "HEREDOC")
        position = end + len(closing)
    return "".join(out) + command[position:]


def mentions(text, names):
    if names is None:
        return "this command"
    return next(
        (n for n in names if re.search(rf"(?<![\w.-]){re.escape(n)}(?![\w.-])", text)),
        None,
    )


def check(command, patterns):
    names = parse_patterns(patterns)
    text = REDIRECTS.sub("", strip_commit_heredocs(command.rstrip("\n")))
    segments, separators, bad = split(text)
    try:
        words = [shlex.split(segment) for segment in segments]
    except ValueError:
        name = mentions(command, names)
        return REASON.format(name) if name else None
    name = next(filter(None, (excluded(w, names) for w in words)), None)
    if name is None:
        name = mentions(command, names) if re.search(r"\$\(|`", command) else None
        return REASON.format(name) if name else None
    if names is None:
        return REASON.format(name) if bad or separators else None
    if separators and separators[0] == "&&" and CD.fullmatch(segments[0].strip()):
        words, separators = words[1:], separators[1:]
    if separators and separators[-1] == "|" and words[-1] and safe_filter(words[-1]):
        words, separators = words[:-1], separators[:-1]
    if not words[-1] and separators and separators[-1] == ";":
        words, separators = words[:-1], separators[:-1]
    if bad or "|" in separators or not all(excluded(w, names) for w in words):
        return REASON.format(name)
    return None


def load_patterns(cwd):
    paths = [Path.home() / ".claude" / "settings.json"]
    for root in (cwd, os.environ.get("CLAUDE_PROJECT_DIR")):
        if root:
            paths += [
                Path(root, ".claude", n)
                for n in ("settings.json", "settings.local.json")
            ]
    patterns = []
    for path in paths:
        if not path.exists():
            continue
        try:
            value = json.loads(path.read_text(encoding="utf-8"))["sandbox"][
                "excludedCommands"
            ]
        except KeyError:
            continue
        except (OSError, ValueError, TypeError):
            value = None
        ok = isinstance(value, list) and all(isinstance(v, str) for v in value)
        patterns += value if ok else ["*"]
    return patterns


def main():
    raw, patterns = "", None
    try:
        raw = sys.stdin.read()
        event = json.loads(raw)
        patterns = load_patterns(event.get("cwd"))
        command = event["tool_input"]["command"]
        if not isinstance(command, str):
            raise TypeError("command is not a string")
        reason = check(command, patterns)
    except Exception:
        name = (
            "this command"
            if patterns is None
            else mentions(raw, parse_patterns(patterns))
        )
        reason = REASON.format(name) if name else None
    if reason:
        decision = {"permissionDecision": "deny", "permissionDecisionReason": reason}
        print(
            json.dumps(
                {"hookSpecificOutput": {"hookEventName": "PreToolUse", **decision}}
            )
        )


if __name__ == "__main__":
    main()
