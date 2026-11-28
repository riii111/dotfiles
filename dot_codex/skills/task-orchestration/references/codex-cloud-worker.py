import argparse
import json
import os
from pathlib import Path
import re
import sqlite3
import uuid


def main():
    parser = argparse.ArgumentParser(description="Track a Codex Cloud worker by task.")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("get", "prepare", "attach"):
        command = commands.add_parser(name)
        command.add_argument("repository")
        command.add_argument("task_id")
        if name == "attach":
            command.add_argument("thread_id", type=uuid.UUID)
    args = parser.parse_args()
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repository, re.ASCII):
        parser.error("repository must be owner/repo")
    if not args.task_id or args.task_id != args.task_id.strip():
        parser.error("task_id must be nonempty and have no surrounding whitespace")

    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    database = state / "task-orchestration" / "codex-cloud-workers.sqlite3"
    key = (args.repository.lower(), args.task_id)
    try:
        read_only = args.command == "get"
        if read_only:
            if not database.exists():
                print("null")
                return
        else:
            database.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        target = f"{database.absolute().as_uri()}?mode=ro" if read_only else database
        with sqlite3.connect(target, uri=read_only) as db:
            if not read_only:
                db.execute("""
                    CREATE TABLE IF NOT EXISTS workers (
                        repository TEXT NOT NULL,
                        task_id TEXT NOT NULL,
                        thread_id TEXT UNIQUE,
                        PRIMARY KEY (repository, task_id)
                    )
                    """)
            if args.command == "prepare":
                created = (
                    db.execute(
                        "INSERT OR IGNORE INTO workers (repository, task_id) VALUES (?, ?)",
                        key,
                    ).rowcount
                    == 1
                )
            if args.command == "attach":
                thread_id = str(args.thread_id)
                updated = db.execute(
                    """
                    INSERT INTO workers (repository, task_id, thread_id) VALUES (?, ?, ?)
                    ON CONFLICT (repository, task_id) DO UPDATE SET thread_id = excluded.thread_id
                    WHERE workers.thread_id IS NULL OR workers.thread_id = excluded.thread_id
                    """,
                    (*key, thread_id),
                ).rowcount
                if not updated:
                    parser.error("this task is already attached to a different worker")
            row = db.execute(
                "SELECT thread_id FROM workers WHERE repository = ? AND task_id = ?",
                key,
            ).fetchone()
    except sqlite3.IntegrityError:
        parser.error("this worker is already attached to a different task")
    except (OSError, sqlite3.Error) as error:
        parser.exit(1, f"could not read or save worker registration: {error}\n")

    result = None
    if row:
        result = {"status": "pending"}
        if row[0]:
            result = {"status": "attached", "hostId": "durable", "threadId": row[0]}
    if args.command == "prepare":
        result["created"] = created
    print(json.dumps(result))


if __name__ == "__main__":
    main()
