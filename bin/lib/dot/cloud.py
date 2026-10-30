"""Install shared skills and portable hooks, preserving user-edited files."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import stat
import sys
from dataclasses import dataclass, field
from pathlib import Path


MANIFEST_NAME = ".dotfiles-cloud-manifest.json"
DEFAULT_SKILLS = (
    "task-orchestration",
    "task-worker",
    "task-session-launch",
    "task-review-cycle",
    "task-dispatch",
    "pr-watch-link",
)
SKILL_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
CLOUD_CLAUDE_HOME = Path("/workspace/.cloud-setup/claude")

# Hooks whose scripts use only the standard library, git and gh.
CLAUDE_HOOKS = (
    "github-comment-check.py",
    "git-force-check.py",
    "pr-format-check.py",
    "pr-state-check.py",
)
CODEX_HOOKS = (
    "github-comment-check.py",
    "pr-format-check.py",
    "pr-state-check.py",
)
# The Codex copy of this hook denies instead of asking (dot_codex/hooks/pr-state-check.py.tmpl).
# Cloud runs without a person to answer, so Claude's copy is made to deny as well.
ASK_TO_DENY = ('MERGE_DECISION = "ask"', 'MERGE_DECISION = "deny"')


class InstallError(Exception):
    pass


@dataclass
class Plan:
    # target path -> (content, mode)
    files: dict[Path, tuple[bytes, int]] = field(default_factory=dict)
    skipped: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def read_source(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise InstallError(f"{path} is not a regular file")
    return path.read_bytes()


def collect_skill(repo: Path, name: str, destinations: tuple[Path, ...], plan: Plan) -> None:
    if not SKILL_NAME.match(name):
        raise InstallError(f"invalid skill name: {name}")
    root = repo / "dot_codex" / "skills" / name
    if root.is_symlink() or not root.is_dir():
        raise InstallError(f"skill {name} does not exist in dot_codex/skills")
    for source in sorted(root.rglob("*")):
        relative = source.relative_to(root)
        if source.is_symlink():
            raise InstallError(f"{source} is a symlink; skills are copied as plain files")
        if source.is_dir():
            continue
        if source.name.endswith(".tmpl"):
            plan.skipped.append(f"{name}/{relative} (chezmoi template; render it with chezmoi)")
            continue
        mode = 0o755 if source.stat().st_mode & stat.S_IXUSR else 0o644
        content = read_source(source)
        for dest in destinations:
            plan.files[dest / name / relative] = (content, mode)


LINK = re.compile(r"\]\(([^)\s]+)\)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


FENCE = re.compile(r"^(`{3,}|~{3,}).*?^\1[ \t]*$", re.MULTILINE | re.DOTALL)
INLINE_CODE = re.compile(r"`[^`\n]*`")


def relative_links(text: str) -> list[str]:
    # Examples in code are not links.
    text = INLINE_CODE.sub("", FENCE.sub("", text))
    targets = []
    for raw in LINK.findall(text):
        target = raw.split("#", 1)[0]
        if not target or target.startswith(("/", "{", "<")) or SCHEME.match(target):
            continue
        targets.append(target)
    return targets


def with_linked_skills(repo: Path, requested: tuple[str, ...]) -> tuple[str, ...]:
    """Adds the skills that the requested skills link to, so no link is left dangling."""
    skills_root = repo / "dot_codex" / "skills"
    names = list(requested)
    index = 0
    while index < len(names):
        root = skills_root / names[index]
        index += 1
        if root.is_symlink() or not root.is_dir():
            continue
        for source in sorted(root.rglob("*.md")):
            if source.is_symlink() or not source.is_file():
                continue
            for target in relative_links(source.read_text(encoding="utf-8")):
                resolved = Path(os.path.normpath(source.parent / target))
                try:
                    inside = resolved.relative_to(skills_root)
                except ValueError:
                    raise InstallError(f"{source.relative_to(repo)} links outside the skills: {target}")
                owner = inside.parts[0] if inside.parts else ""
                if not SKILL_NAME.match(owner):
                    raise InstallError(f"{source.relative_to(repo)} has a link to {target} that is not in a skill")
                if owner not in names:
                    names.append(owner)
    return tuple(names)


def claude_settings(claude_home: Path) -> bytes:
    def command(script: str, extra: str = "") -> dict[str, object]:
        return {
            "type": "command",
            "command": f"python3 {shlex.quote(str(claude_home / 'hooks' / script))}{extra}",
            "timeout": 15 if script == "pr-state-check.py" else 5,
        }

    settings = {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "^(Bash|mcp__.*)$",
                    "hooks": [command("github-comment-check.py")],
                },
                {
                    "matcher": "Bash",
                    "hooks": [
                        command("git-force-check.py", " --deny-force-push"),
                        command("pr-format-check.py"),
                        command("pr-state-check.py"),
                    ],
                },
            ]
        }
    }
    return (json.dumps(settings, indent=2) + "\n").encode()


def codex_hooks(codex_home: Path) -> bytes:
    def command(script: str, status: str, timeout: int = 5) -> dict[str, object]:
        return {
            "type": "command",
            "command": f"python3 {shlex.quote(str(codex_home / 'hooks' / script))}",
            "timeout": timeout,
            "statusMessage": status,
        }

    hooks = {
        "description": "Cloud subset of the dotfiles Codex hooks.",
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "^Bash$",
                    "hooks": [
                        command("pr-format-check.py", "Checking PR format"),
                        command("pr-state-check.py", "Checking PR state", 15),
                    ],
                },
                {
                    "matcher": "^(Bash|mcp__.*)$",
                    "hooks": [
                        command("github-comment-check.py", "Checking GitHub comment policy")
                    ],
                },
            ]
        },
    }
    return (json.dumps(hooks, indent=2) + "\n").encode()


def build_plan(
    repo: Path,
    codex_home: Path,
    claude_home: Path,
    skills: tuple[str, ...],
    with_hooks: bool,
) -> Plan:
    plan = Plan()
    for target in (codex_home, claude_home):
        if not target.is_absolute():
            raise InstallError(f"{target} is not an absolute path")
    skills = with_linked_skills(repo, skills)
    destinations = (codex_home / "skills", claude_home / "skills")
    for name in skills:
        collect_skill(repo, name, destinations, plan)
    plan.notes.append("Skills installed: " + ", ".join(skills))
    if not with_hooks:
        return plan
    claude_sources = repo / "dot_claude" / "hooks"
    for script in CLAUDE_HOOKS:
        content = read_source(claude_sources / f"executable_{script}")
        if script == "pr-state-check.py":
            old, new = ASK_TO_DENY
            if old.encode() not in content:
                raise InstallError(f"{script} no longer contains {old}; update ASK_TO_DENY")
            content = content.replace(old.encode(), new.encode())
        plan.files[claude_home / "hooks" / script] = (content, 0o755)
    plan.files[claude_home / "settings.json"] = (claude_settings(claude_home), 0o644)
    # The Codex copies are the same scripts, so they come from the same source.
    for script in CODEX_HOOKS:
        plan.files[codex_home / "hooks" / script] = (
            plan.files[claude_home / "hooks" / script][0],
            0o755,
        )
    plan.files[codex_home / "hooks.json"] = (codex_hooks(codex_home), 0o644)
    plan.notes += [
        "Hooks not carried over: the prompt-type PR judge, the find/grep/cat redirect, permission logging,",
        "worktree post-add, status line, herdr and affected-agent (local tools or machine paths).",
        "Codex permission_request.py is not installed: its allow rules assume ~/ghq and ~/agent-desk.",
        "pr-format-check blocks gh pr create/edit until `git config pr.language ja|en` is set in the repository.",
        "Codex reads hooks.json only with `hooks = true` under [features] in config.toml; this command does not edit config.toml.",
        "Whether Cloud loads these skills and hooks automatically is not verified; check it in the task.",
    ]
    return plan


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def load_manifest(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise InstallError(f"{path} is unreadable: {error}")
    files = data.get("files") if isinstance(data, dict) else None
    if not isinstance(files, dict):
        raise InstallError(f"{path} has no files table")
    return {str(key): str(value) for key, value in files.items()}


def check_chain(path: Path, home: Path) -> None:
    """Refuses a symlink anywhere from the home directory down to path.

    The home is the directory the caller chose, so a link at the home itself is
    followed once; everything below it must be plain directories and files.
    """
    real_home = home.resolve()
    try:
        relative = path.relative_to(home)
    except ValueError:
        raise InstallError(f"{path} is outside {home}")
    current = real_home
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise InstallError(f"{current} is a symlink; refusing to write through or replace it")
        if not current.exists():
            break


def check_target(path: Path, content: bytes, managed: dict[str, str], home: Path) -> str:
    """Returns create, update or same; raises when the file is not ours."""
    check_chain(path, home)
    if not path.exists():
        return "create"
    current = path.read_bytes()
    if current == content:
        return "same"
    if managed.get(str(path)) == digest(current):
        return "update"
    raise InstallError(
        f"{path} exists and was not written by this command (or was edited since); "
        "move it away or merge it by hand"
    )


def check_writable(home: Path) -> None:
    probe = home
    while not probe.exists():
        probe = probe.parent
    if not probe.is_dir() or not os.access(probe, os.W_OK | os.X_OK):
        raise InstallError(
            f"{home} cannot be written ({probe} is read-only here). "
            "Pass a writable directory with --codex-home and --claude-home, "
            "for example /workspace/.cloud-setup/codex and /workspace/.cloud-setup/claude"
        )


def write_file(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    os.chmod(path, mode)


def home_of(path: Path, homes: tuple[Path, ...]) -> Path:
    return next(home for home in homes if home in path.parents)


def apply_plan(plan: Plan, homes: tuple[Path, ...], apply: bool) -> list[str]:
    manifests = {home: home / MANIFEST_NAME for home in homes}
    managed: dict[str, str] = {}
    existing = {}
    for home, manifest in manifests.items():
        check_chain(manifest, home)
        existing[home] = load_manifest(manifest)
        managed.update(existing[home])
    actions = {
        path: check_target(path, content, managed, home_of(path, homes))
        for path, (content, _) in plan.files.items()
    }
    lines = [f"{action:6} {path}" for path, action in sorted(actions.items())]
    if not apply:
        return lines
    for home in homes:
        check_writable(home)
    for path, (content, mode) in plan.files.items():
        if actions[path] != "same":
            write_file(path, content, mode)
    for home, manifest in manifests.items():
        recorded = {
            str(path): digest(content)
            for path, (content, _) in plan.files.items()
            if home in path.parents
        }
        previous = existing[home]
        previous.update(recorded)
        write_file(manifest, (json.dumps({"files": previous}, indent=2, sort_keys=True) + "\n").encode(), 0o644)
    return lines


def default_codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")


def default_claude_home() -> Path:
    configured = os.environ.get("CLAUDE_CONFIG_DIR")
    if configured:
        return Path(configured)
    return CLOUD_CLAUDE_HOME if CLOUD_CLAUDE_HOME.is_dir() else Path.home() / ".claude"


def run(
    repo: Path,
    codex_home: Path,
    claude_home: Path,
    skills: tuple[str, ...],
    with_hooks: bool,
    apply: bool,
) -> int:
    try:
        plan = build_plan(repo, codex_home, claude_home, skills, with_hooks)
        lines = apply_plan(plan, (codex_home, claude_home), apply)
    except (InstallError, OSError) as error:
        print(f"cloud-install: {error}", file=sys.stderr)
        return 1
    print("\n".join(lines))
    for skipped in plan.skipped:
        print(f"skip   {skipped}")
    for note in plan.notes:
        print(f"note: {note}")
    print("applied" if apply else "dry run only; rerun with --apply to write")
    return 0
