#!/usr/bin/env python3
import json
from pathlib import Path


path = Path.home() / ".config/pr-wake/review.json"
if path.is_file():
    config = json.loads(path.read_text())
    changed = False
    for choice in config["choices"]:
        if choice["skill"] in {"code-review", "adr-review"}:
            # Saved re-requests refer to choice IDs, so only the skill is replaced.
            choice["skill"] = "pr-review"
            changed = True
    if changed:
        path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
        print(
            "Updated pr-wake review choices to pr-review; restart pr-wake review to load them."
        )
