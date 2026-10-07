#!/usr/bin/env python3
"""Deny Bash commands that join a sandbox-excluded program with other code.

Claude Code decides sandbox exclusion for the whole command string: a command
that matches sandbox.excludedCommands (for example `git *`) runs entirely
outside the sandbox. `git status; cp x ~/.local/bin/y` would then run the `cp`
unsandboxed, and each part can still match an allow rule, so nothing prompts.
This hook denies such commands unless the excluded program runs alone.

The shell parsing is deliberately conservative: when unsure, it denies.
"""

import json
import os
import re
import sys
from pathlib import Path

# Commands that run the next word as a program, and shell keywords that can
# precede one. When a segment starts with one of these, every word is checked.
WRAPPERS = {
    "!",
    "{",
    "}",
    "builtin",
    "caffeinate",
    "chronic",
    "command",
    "do",
    "doas",
    "done",
    "elif",
    "else",
    "env",
    "eval",
    "exec",
    "fi",
    "flock",
    "if",
    "ionice",
    "nice",
    "nohup",
    "setsid",
    "stdbuf",
    "sudo",
    "then",
    "time",
    "timeout",
    "unbuffer",
    "until",
    "watch",
    "while",
    "xargs",
    "bash",
    "sh",
    "zsh",
}
# Read-only filters allowed after a final pipe. jq cannot run programs or
# write files; head, tail and wc are limited to plain counts.
SAFE_PIPE = re.compile(r"(head|tail)( (-n ?|-c ?|-)[0-9]+)?|wc( -[lcmw]+)?|jq( .*)?")
SAFE_TARGETS = {"/dev/null", "/dev/stdout", "/dev/stderr"}
HEREDOC_SUBST = re.compile(r"\$\(\s*cat\s+<<(-?)\s*(['\"])([A-Za-z_][A-Za-z0-9_]*)\2\n")
REASON = (
    "{name} is excluded from the sandbox, so this whole command would run "
    "unsandboxed. Run the {name} command alone: no ;, &&, ||, |, &, newlines, "
    "$(...), backticks, process substitution or redirection to files "
    "(2>&1, >/dev/null and a final | head, tail, wc or jq are fine). "
    "Use `git -C <dir>` instead of `cd <dir> && git`. Problem: {problem}"
)


def excluded_names(patterns):
    """Map each excluded program to the literal words that follow it.

    `cargo test *` gives {"cargo": [("test",)]}. None means every command.
    """
    names = {}
    for pattern in patterns:
        words = str(pattern).replace(":*", " *").split()
        first = words[0] if words else ""
        if not first or any(char in first for char in "*?["):
            return None
        literal = []
        for word in words[1:]:
            if any(char in word for char in "*?["):
                break
            literal.append(word)
        names.setdefault(first.rsplit("/", 1)[-1], []).append(tuple(literal))
    return names


def strip_heredoc_substitutions(command):
    """Replace `$(cat <<'EOF' ... EOF)` with a literal word.

    A quoted delimiter keeps the body literal, so only `cat` runs. The body
    must end at the first delimiter line and be followed directly by `)`.
    """
    result = []
    position = 0
    while True:
        match = HEREDOC_SUBST.search(command, position)
        if match is None:
            break
        strip_tabs, delimiter = match.group(1) == "-", match.group(3)
        lines_start = match.end()
        cursor = lines_start
        end = None
        while cursor <= len(command):
            newline = command.find("\n", cursor)
            line = command[cursor:] if newline == -1 else command[cursor:newline]
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                after = command[cursor + len(line) :]
                closing = re.match(r"\s*\)", after)
                if closing:
                    end = cursor + len(line) + closing.end()
                break
            if newline == -1:
                break
            cursor = newline + 1
        if end is None:
            result.append(command[position : match.end()])
            position = match.end()
            continue
        result.append(command[position : match.start()])
        result.append("HEREDOC")
        position = end
    result.append(command[position:])
    return "".join(result)


class Lexer:
    """Split a shell command into segments and record risky constructs."""

    def __init__(self, command):
        self.text = command
        self.i = 0
        self.segments = [("", [])]
        self.word = None
        self.word_digits = True
        self.redirect = None
        self.heredocs = []
        self.problems = []
        self.substitution = False

    def peek(self, offset=0):
        index = self.i + offset
        return self.text[index] if index < len(self.text) else ""

    def add(self, text):
        if self.word is None:
            self.word = ""
        self.word += text

    def end_word(self):
        if self.word is None:
            return
        word, self.word = self.word, None
        target, self.redirect = self.redirect, None
        if target == "out":
            if word not in SAFE_TARGETS:
                self.problems.append(f"redirection to {word}")
        elif target == "heredoc":
            pass
        elif target != "in":
            self.segments[-1][1].append(word)

    def separator(self, token):
        self.end_word()
        if self.redirect is not None:
            self.problems.append(f"redirection before {token!r}")
            self.redirect = None
        self.segments.append((token, []))

    def substitute(self, token):
        self.substitution = True
        self.problems.append(f"{token} substitution")
        self.separator(token)

    def read_heredoc_delimiter(self, strip_tabs):
        while self.peek() in (" ", "\t"):
            self.i += 1
        start = self.i
        while self.peek() and self.peek() not in " \t\n;&|<>()":
            if self.peek() in "'\"":
                quote = self.peek()
                end = self.text.find(quote, self.i + 1)
                self.i = len(self.text) if end == -1 else end + 1
            else:
                self.i += 1
        raw = self.text[start : self.i]
        quoted = any(char in raw for char in "'\"\\")
        delimiter = raw.replace("'", "").replace('"', "").replace("\\", "")
        self.heredocs.append((delimiter, quoted, strip_tabs))

    def read_heredoc_bodies(self):
        for delimiter, quoted, strip_tabs in self.heredocs:
            while self.i < len(self.text):
                newline = self.text.find("\n", self.i)
                end = len(self.text) if newline == -1 else newline
                line = self.text[self.i : end]
                self.i = end + 1
                if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                    break
                if not quoted and re.search(r"(?<!\\)(\$\(|`)", line):
                    self.substitution = True
                    self.problems.append("substitution in a heredoc")
        self.heredocs = []

    def double_quoted(self):
        self.i += 1
        self.add("")
        while self.i < len(self.text):
            char = self.peek()
            if char == '"':
                self.i += 1
                return
            if char == "\\" and self.peek(1) in ('"', "\\", "$", "`", "\n"):
                if self.peek(1) != "\n":
                    self.add(self.peek(1))
                self.i += 2
                continue
            if char == "`" or (char == "$" and self.peek(1) == "("):
                self.substitution = True
                self.problems.append("substitution inside double quotes")
            self.add(char)
            self.i += 1
        self.problems.append("unterminated double quote")

    def run(self):
        while self.i < len(self.text):
            char, next_char = self.peek(), self.peek(1)
            if char == "\\":
                if next_char != "\n":
                    self.add(next_char)
                self.i += 2
            elif char == "'":
                end = self.text.find("'", self.i + 1)
                if end == -1:
                    self.problems.append("unterminated single quote")
                    end = len(self.text)
                self.add(self.text[self.i + 1 : end])
                self.i = end + 1
            elif char == "$" and next_char == "'":
                end = self.i + 2
                while end < len(self.text) and self.text[end] != "'":
                    end += 2 if self.text[end] == "\\" else 1
                self.add(self.text[self.i + 2 : end])
                self.i = end + 1
            elif char == '"':
                self.double_quoted()
            elif char == "$" and next_char == "(":
                self.i += 2
                self.substitute("$(")
            elif char == "`":
                self.i += 1
                self.substitute("`")
            elif char in "<>" and next_char == "(":
                self.i += 2
                self.substitute(char + "(")
            elif char == "#" and self.word is None:
                newline = self.text.find("\n", self.i)
                self.i = len(self.text) if newline == -1 else newline
            elif char in " \t":
                self.end_word()
                self.i += 1
            elif char == "\n":
                self.i += 1
                self.separator("\n")
                self.read_heredoc_bodies()
            elif char == "&" and next_char == ">":
                self.end_word()
                self.i += 3 if self.peek(2) == ">" else 2
                self.redirect = "out"
            elif char == ">":
                if self.word is not None and self.word.isdigit():
                    self.word = None
                self.end_word()
                self.i += 1
                if self.peek() in (">", "|"):
                    self.i += 1
                if self.peek() == "&":
                    self.i += 1
                    match = re.match(r"[0-9]+-?|-", self.text[self.i :])
                    if match:
                        self.i += match.end()
                        continue
                self.redirect = "out"
            elif char == "<":
                if self.word is not None and self.word.isdigit():
                    self.word = None
                self.end_word()
                if self.text.startswith("<<<", self.i):
                    self.i += 3
                elif next_char == "<":
                    self.i += 2
                    strip_tabs = self.peek() == "-"
                    self.i += 1 if strip_tabs else 0
                    self.read_heredoc_delimiter(strip_tabs)
                elif next_char == ">":
                    self.i += 2
                    self.redirect = "out"
                elif next_char == "&":
                    self.i += 2
                    match = re.match(r"[0-9]+-?|-", self.text[self.i :])
                    self.i += match.end() if match else 0
                else:
                    self.i += 1
                    self.redirect = "in"
            elif char in ";&|()":
                token = char
                if self.text.startswith(("&&", "||", ";;", "|&"), self.i):
                    token = self.text[self.i : self.i + 2]
                self.i += len(token)
                self.separator(token)
            else:
                self.add(char)
                self.i += 1
        self.end_word()
        if self.redirect is not None:
            self.problems.append("redirection without a target")
        self.read_heredoc_bodies()
        return self


def basename(word):
    return word.rsplit("/", 1)[-1]


def matches(words, literals):
    """Whether the words after a program contain every literal word in order.

    Options may sit between them, so this matches more than Claude Code does.
    """
    for literal in literals:
        rest = iter(words)
        if all(word in rest for word in literal):
            return True
    return False


def runs_excluded(words, names):
    if not words:
        return None
    if names is None:
        return basename(words[0])
    index = 0
    while index < len(words) and re.match(r"[A-Za-z_][A-Za-z0-9_]*=", words[index]):
        index += 1
    if index == len(words):
        return None
    last = len(words) if basename(words[index]) in WRAPPERS else index + 1
    for position in range(index, last):
        name = basename(words[position])
        if name in names and matches(words[position + 1 :], names[name]):
            return name
    return None


def raw_mentions(command, names):
    if names is None:
        return "this command"
    for name in sorted(names):
        if re.search(rf"(?<![\w.-]){re.escape(name)}(?![\w.-])", command):
            return name
    return None


def check(command, patterns):
    """Return a deny reason, or None when the command may run as is."""
    names = excluded_names(patterns)
    if names is not None and not names:
        return None
    try:
        lexer = Lexer(strip_heredoc_substitutions(command)).run()
    except Exception as error:  # Unknown syntax: decide from the raw text.
        name = raw_mentions(command, names)
        return (
            REASON.format(name=name, problem=f"parse error: {error}") if name else None
        )
    segments = [(token, words) for token, words in lexer.segments if words]
    excluded = None
    for _, words in segments:
        excluded = excluded or runs_excluded(words, names)
    if excluded is None and lexer.substitution:
        excluded = raw_mentions(command, names)
    if excluded is None:
        return None
    problems = list(lexer.problems)
    for position, (token, words) in enumerate(segments):
        if position == 0:
            continue
        if token == "|" and SAFE_PIPE.fullmatch(" ".join(words)):
            continue
        problems.append(f"{token!r} joins another command")
    if not problems:
        return None
    return REASON.format(name=excluded, problem="; ".join(problems))


def load_patterns(cwd):
    paths = [Path.home() / ".claude" / "settings.json"]
    for root in {cwd, os.environ.get("CLAUDE_PROJECT_DIR")}:
        if root:
            paths += [
                Path(root, ".claude", name)
                for name in ("settings.json", "settings.local.json")
            ]
    patterns = []
    for path in paths:
        try:
            settings = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            continue
        except (OSError, ValueError):
            patterns.append("*")
            continue
        sandbox = settings.get("sandbox") if isinstance(settings, dict) else None
        if isinstance(sandbox, dict):
            patterns += sandbox.get("excludedCommands") or []
    return patterns


def main():
    event = json.load(sys.stdin)
    tool_input = event.get("tool_input") or {}
    command = tool_input.get("command")
    if event.get("tool_name", "Bash") != "Bash" or not isinstance(command, str):
        return 0
    reason = check(command, load_patterns(event.get("cwd")))
    if reason:
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            },
            sys.stdout,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
