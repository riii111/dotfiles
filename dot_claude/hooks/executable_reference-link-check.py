#!/usr/bin/env python3
"""Only explicit Issue/PR references are unambiguous enough to block a reply."""

import json
import re
import sys


def missing_links(message: str) -> bool:
    message = re.sub(r"(?ms)^\s*(`{3,}|~{3,}).*?^\s*\1[^\n]*$", "", message)
    message = re.sub(r"(?m)^\s*>.*$", "", message)
    message = re.sub(r"`[^`\n]*`", "", message)
    message = re.sub(r"\[[^\]]*\]\(https?://[^\s)]+\)", "", message)
    return bool(
        re.search(r"(?<![A-Za-z0-9_])(?:Issue|PR)\s*#\d+(?!\d)", message, re.IGNORECASE)
    )


def main() -> int:
    event = json.load(sys.stdin)
    if not event.get("stop_hook_active") and missing_links(
        event.get("last_assistant_message") or ""
    ):
        print(
            json.dumps(
                {
                    "decision": "block",
                    # The reply is already shown, so a rewrite would show it twice.
                    "reason": "回答全体は繰り返さないでください。リンクのないIssue #N・PR #Nへの"
                    "Markdownリンクだけを「参照: [PR #1](URL)」の形で1〜2行で追記してください。",
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
