"""Collect advisory Git metadata and render a validated plugin update report."""

import argparse
import json
from pathlib import Path
import re
import subprocess

NAME = re.compile(r"[A-Za-z0-9_.-]+")
BRANCH = re.compile(r"[A-Za-z0-9_./-]+")
SHA = re.compile(r"[0-9a-f]{40}")
TAG = re.compile(r"[0-9A-Za-z][0-9A-Za-z._+-]{0,63}")
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*")


def matches(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def validate_lock(lock):
    if not isinstance(lock, dict) or not lock:
        raise ValueError("Invalid lockfile")
    for name, entry in lock.items():
        if not matches(NAME, name):
            raise ValueError("Invalid plugin name")
        if not isinstance(entry, dict) or not (
            set(entry) == {"branch", "commit"}
            and matches(BRANCH, entry.get("branch"))
            and matches(SHA, entry.get("commit"))
        ):
            raise ValueError("Invalid lockfile entry")


def render_report(before, after, report):
    validate_lock(before)
    validate_lock(after)
    if not isinstance(report, dict) or any(not matches(NAME, name) for name in report):
        raise ValueError("Invalid report plugin name")
    rows = []
    attention = []
    for name in sorted(before.keys() | after.keys()):
        old, new = before.get(name), after.get(name)
        info = report.get(name)
        info = info if isinstance(info, dict) else {}
        old_sha = old["commit"] if old else None
        new_sha = new["commit"] if new else None
        if old != new:
            versions = []
            for side, commit in (("old", old_sha), ("new", new_sha)):
                tag = info.get(f"{side}_version")
                versions.append(
                    tag
                    if commit and matches(TAG, tag)
                    else (commit[:7] if commit else "—")
                )
            count = info.get("commits")
            count = (
                str(count) if old and new and type(count) is int and count >= 0 else "—"
            )
            repository = info.get("repository")
            if matches(REPOSITORY, repository) and old and new:
                compare = f"[compare](https://github.com/{repository}/compare/{old_sha}...{new_sha})"
            else:
                compare = (
                    f"`{old_sha[:7] if old else '—'}...{new_sha[:7] if new else '—'}`"
                )
            rows.append(
                f"| `{name}` | `{versions[0]} → {versions[1]}` | {count} | {compare} |"
            )
            if old is None:
                attention.append(f"- `{name}`: プラグインの追加")
            elif new is None:
                attention.append(f"- `{name}`: プラグインの削除")
            else:
                if old["branch"] != new["branch"]:
                    attention.append(
                        f"- `{name}`: ブランチ変更 `{old['branch']} → {new['branch']}`"
                    )
                if old_sha != new_sha and info.get("fast_forward") is not True:
                    reason = (
                        "fast-forwardではない更新"
                        if info.get("fast_forward") is False
                        else "履歴の前後関係を確認できない更新"
                    )
                    attention.append(f"- `{name}`: {reason}")
        outside_sha = info.get("outside_commit")
        if new and matches(SHA, outside_sha):
            tag = info.get("outside_version")
            version = tag if matches(TAG, tag) else outside_sha[:7]
            attention.append(
                f"- `{name}`: 制約外の新版あり `{version}`（自動更新対象外）"
            )

    body = ["Neovimプラグインを更新する。", ""]
    if rows:
        body += [
            "| プラグイン | 旧 → 新 | コミット数 | 差分 |",
            "| --- | --- | ---: | --- |",
            *rows,
        ]
    else:
        body.append("No plugin changes.")
    if attention:
        body += ["", "## Needs attention", "", *attention]
    body += [
        "",
        "バージョン等の情報はプラグインを実行したランナーで収集した参考情報。正とするのはlockfileの差分とcompareリンク。",
        "",
        "Ready for reviewにするとCIが起動する。適用・切り戻し手順はREADMEを参照。",
    ]
    return "\n".join(body) + "\n"


def collect_report(before, after, lazy_root, constraints, env):
    validate_lock(before)
    validate_lock(after)

    def git(directory, *args):
        return subprocess.run(
            ["git", "-C", str(directory), *args],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    report = {}
    for name in sorted(before.keys() | after.keys()):
        directory = lazy_root / name
        info = {}
        result = git(directory, "remote", "get-url", "origin")
        origin = result.stdout.strip()
        for prefix in ("https://github.com/", "git@github.com:"):
            if origin.startswith(prefix):
                info["repository"] = origin.removeprefix(prefix).removesuffix(".git")
                break
        for side, lock in (("old", before), ("new", after)):
            if name in lock:
                result = git(
                    directory, "describe", "--tags", "--always", lock[name]["commit"]
                )
                if result.returncode == 0:
                    info[f"{side}_version"] = result.stdout.strip()
        if name in before and name in after:
            old, new = before[name]["commit"], after[name]["commit"]
            result = git(directory, "rev-list", "--count", f"{old}..{new}")
            if result.returncode == 0 and result.stdout.strip().isdigit():
                info["commits"] = int(result.stdout.strip())
            result = git(directory, "merge-base", "--is-ancestor", old, new)
            if result.returncode in (0, 1):
                info["fast_forward"] = result.returncode == 0
        if name in constraints:
            info.update(constraints[name])
        report[name] = info
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    body = render_report(
        *(
            json.loads(path.read_text())
            for path in (args.before, args.after, args.report)
        )
    )
    args.output.write_text(body)


if __name__ == "__main__":
    main()
