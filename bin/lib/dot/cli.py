from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


REQUIRED_COMMANDS = ("git", "python3", "chezmoi", "brew", "nvim", "lefthook", "nix")
OPTIONAL_COMMANDS = ("shellcheck", "shfmt")
LINTABLE_SHELLS = frozenset({"bash", "sh"})
# Keep in sync with NIX_DOTFILES_PROFILE in dot_zshrc.tmpl.
NIX_DOTFILES_PROFILE = (
    Path.home() / ".local" / "state" / "nix" / "profiles" / "dotfiles-cli"
)
NIX_DOTFILES_PROFILE_ELEMENT = "cli"
NIX_DOTFILES_INSTALLABLE = ".#cli"


def run_capture(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(
        list(args),
        check=True,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout.strip()


def resolve_repo_root() -> Path:
    try:
        return Path(run_capture("git", "rev-parse", "--show-toplevel")).resolve()
    except subprocess.CalledProcessError:
        pass

    chezmoi = shutil.which("chezmoi")
    if chezmoi:
        try:
            return Path(run_capture(chezmoi, "source-path")).resolve()
        except subprocess.CalledProcessError:
            pass

    raise RuntimeError("repository root could not be resolved")


def git_tracked_files(repo_root: Path) -> list[Path]:
    output = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repo_root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout.decode()
    return [repo_root / entry for entry in output.split("\0") if entry]


def git_staged_files(repo_root: Path) -> list[Path]:
    output = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR"],
        cwd=repo_root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout.decode()
    return [repo_root / entry for entry in output.split("\0") if entry]


def read_first_line(path: Path) -> str:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return handle.readline().strip()
    except (OSError, UnicodeDecodeError):
        return ""


def detect_shebang_shell(first_line: str) -> str | None:
    if not first_line.startswith("#!"):
        return None

    try:
        tokens = shlex.split(first_line[2:].strip())
    except ValueError:
        return None

    if not tokens:
        return None

    command = Path(tokens[0]).name
    if command == "env":
        command = ""
        for token in tokens[1:]:
            if token.startswith("-"):
                continue
            command = Path(token).name
            break
        if not command:
            return None

    if command.startswith("python"):
        return None
    if command in {"zsh", "bash", "sh"}:
        return command
    return None


def detect_shell(path: Path) -> str | None:
    suffix = path.suffix
    # `.zsh` files in this repo are intentionally treated as zsh scripts
    # even if the shebang is omitted or differs.
    if suffix == ".zsh":
        return "zsh"

    shell = detect_shebang_shell(read_first_line(path))
    if shell is not None:
        return shell
    if suffix == ".sh":
        return "bash"
    return None


def collect_detected_shell_targets(paths: list[Path]) -> list[tuple[Path, str]]:
    targets: list[tuple[Path, str]] = []
    for path in paths:
        if path.suffix == ".tmpl" or not path.is_file():
            continue
        shell = detect_shell(path)
        if shell is not None:
            targets.append((path, shell))
    return targets


def collect_shell_targets(repo_root: Path) -> list[tuple[Path, str]]:
    return collect_detected_shell_targets(git_tracked_files(repo_root))


def resolve_candidate_paths(repo_root: Path, paths: list[str]) -> list[Path]:
    resolved = []
    for raw in paths:
        path = (
            (repo_root / raw).resolve()
            if not Path(raw).is_absolute()
            else Path(raw).resolve()
        )
        try:
            path.relative_to(repo_root)
        except ValueError:
            continue
        if path.is_file():
            resolved.append(path)
    return resolved


def collect_lintable_shell_targets(paths: list[Path]) -> list[Path]:
    return [
        path
        for path, shell in collect_detected_shell_targets(paths)
        if shell in LINTABLE_SHELLS
    ]


def run_lint_shell_targets(
    repo_root: Path,
    targets: list[Path],
) -> int:
    if not targets:
        return 0

    shfmt = shutil.which("shfmt")
    shellcheck = shutil.which("shellcheck")
    if shfmt is None and shellcheck is None:
        print("Skipping shell lint: shfmt and shellcheck are not installed")
        return 0

    target_args = [str(path.relative_to(repo_root)) for path in targets]
    if shfmt:
        result = run_command([shfmt, "-w", *target_args], repo_root)
        if result.returncode != 0:
            print_process_failure("shfmt", result)
            return 1
    else:
        print("Skipping shfmt: not installed")

    if shellcheck:
        result = run_command([shellcheck, *target_args], repo_root)
        if result.returncode != 0:
            print_process_failure("shellcheck", result)
            return 1
    else:
        print("Skipping shellcheck: not installed")

    return 0


def run_command(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    print("$", shlex.join(args))
    return subprocess.run(args, cwd=cwd, check=False, text=True)


def print_process_failure(
    label: str,
    result: subprocess.CompletedProcess[str],
) -> None:
    print(f"{label}: failed (exit {result.returncode})", file=sys.stderr)
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)
    if result.stdout:
        print(result.stdout.rstrip(), file=sys.stderr)


def command_test(_: argparse.Namespace) -> int:
    repo_root = resolve_repo_root()
    failures = 0

    test_result = run_command(["python3", "-m", "unittest", "discover", "tests"], repo_root)
    if test_result.returncode != 0:
        failures += 1
        print_process_failure("python tests", test_result)

    targets = collect_shell_targets(repo_root)
    if not targets:
        print("No shell targets found")
        return 1 if failures else 0

    print(f"Checking {len(targets)} shell targets")
    shell_failures: list[str] = []
    for path, shell in targets:
        shell_path = shutil.which(shell)
        if shell_path is None:
            shell_failures.append(str(path.relative_to(repo_root)))
            print(
                f"shell syntax ({path.relative_to(repo_root)}): {shell} not found",
                file=sys.stderr,
            )
            continue

        result = subprocess.run(
            [shell_path, "-n", str(path)],
            cwd=repo_root,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            shell_failures.append(str(path.relative_to(repo_root)))
            print_process_failure(
                f"shell syntax ({path.relative_to(repo_root)})",
                result,
            )

    if shell_failures:
        failures += 1
        print(
            "Shell syntax failed: " + ", ".join(shell_failures),
            file=sys.stderr,
        )
    else:
        print("Shell syntax OK")

    return 1 if failures else 0


def command_check_env(_: argparse.Namespace) -> int:
    failures = 0
    missing_required = []
    for name in REQUIRED_COMMANDS:
        path = shutil.which(name)
        print(f"{name}: {'OK' if path else 'MISSING'}")
        if path is None:
            missing_required.append(name)

    missing_optional = []
    for name in OPTIONAL_COMMANDS:
        path = shutil.which(name)
        print(f"{name}: {'OK' if path else 'OPTIONAL'}")
        if path is None:
            missing_optional.append(name)

    nvim = shutil.which("nvim")
    if nvim:
        print("$ nvim --headless +qa")
        result = subprocess.run(
            [nvim, "--headless", "+qa"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode == 0:
            print("nvim headless: OK")
        else:
            failures += 1
            print("nvim headless: FAILED", file=sys.stderr)
            if result.stderr:
                print(result.stderr.rstrip(), file=sys.stderr)
            if result.stdout:
                print(result.stdout.rstrip(), file=sys.stderr)

    if missing_required:
        print(
            "Missing required commands: " + ", ".join(missing_required),
            file=sys.stderr,
        )
        failures += 1

    if missing_optional:
        print("Optional commands not found: " + ", ".join(missing_optional))
    return 1 if failures else 0


def command_lint_shell(args: argparse.Namespace) -> int:
    repo_root = resolve_repo_root()
    targets = collect_lintable_shell_targets(resolve_candidate_paths(repo_root, args.paths))
    return run_lint_shell_targets(repo_root, targets)


def command_lint_staged_shell(_: argparse.Namespace) -> int:
    repo_root = resolve_repo_root()
    targets = collect_lintable_shell_targets(git_staged_files(repo_root))
    return run_lint_shell_targets(repo_root, targets)


def command_sync_nix_profile(_: argparse.Namespace) -> int:
    repo_root = resolve_repo_root()
    nix = shutil.which("nix")
    if nix is None:
        raise RuntimeError("nix is not installed")

    NIX_DOTFILES_PROFILE.parent.mkdir(parents=True, exist_ok=True)
    listing = json.loads(
        run_capture(
            nix,
            "profile",
            "list",
            "--profile",
            str(NIX_DOTFILES_PROFILE),
            "--json",
        )
    )

    if NIX_DOTFILES_PROFILE_ELEMENT in listing.get("elements", {}):
        result = run_command(
            [
                nix,
                "profile",
                "upgrade",
                "--profile",
                str(NIX_DOTFILES_PROFILE),
                NIX_DOTFILES_PROFILE_ELEMENT,
            ],
            repo_root,
        )
        if result.returncode != 0:
            print_process_failure("nix profile upgrade", result)
            return 1
    else:
        result = run_command(
            [
                nix,
                "profile",
                "add",
                "--profile",
                str(NIX_DOTFILES_PROFILE),
                NIX_DOTFILES_INSTALLABLE,
            ],
            repo_root,
        )
        if result.returncode != 0:
            print_process_failure("nix profile add", result)
            return 1

    print(f"Nix CLI profile synced: {NIX_DOTFILES_PROFILE}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="dot")
    subparsers = parser.add_subparsers(dest="command", required=True)

    test_parser = subparsers.add_parser("test", help="run repo verification")
    test_parser.set_defaults(func=command_test)

    env_parser = subparsers.add_parser("check-env", help="check local toolchain")
    env_parser.set_defaults(func=command_check_env)

    lint_shell_parser = subparsers.add_parser(
        "lint-shell",
        help="format and lint bash/sh files",
    )
    lint_shell_parser.add_argument("paths", nargs="*")
    lint_shell_parser.set_defaults(func=command_lint_shell)

    lint_staged_shell_parser = subparsers.add_parser(
        "lint-staged-shell",
        help="format and lint staged bash/sh files",
    )
    lint_staged_shell_parser.set_defaults(func=command_lint_staged_shell)

    nix_profile_parser = subparsers.add_parser(
        "sync-nix-profile",
        help="install/update the dotfiles Nix CLI profile",
    )
    nix_profile_parser.set_defaults(func=command_sync_nix_profile)

    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
        return args.func(args)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"Error: {' '.join(str(part) for part in exc.cmd)}", file=sys.stderr)
        if exc.stderr:
            print(exc.stderr.rstrip(), file=sys.stderr)
        return exc.returncode or 1
