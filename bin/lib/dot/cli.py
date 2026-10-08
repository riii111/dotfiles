from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple


LINTABLE_SHELLS = frozenset({"bash", "sh"})
# chezmoi source names of the zsh startup files. They have neither a shebang nor an
# extension, and may carry attribute prefixes such as private_.
ZSH_STARTUP_FILES = (
    "dot_zshenv",
    "dot_zprofile",
    "dot_zshrc",
    "dot_zlogin",
    "dot_zlogout",
)
# The machine types of .chezmoi.toml.tmpl. Shell templates are rendered for each of
# them with the static data in tests/chezmoi/<machine type>.toml.
MACHINE_TYPES = ("personal", "work")
CHEZMOI_TEST_DATA_DIR = Path("tests") / "chezmoi"
# Keep in sync with NIX_DOTFILES_PROFILE in dot_zshrc.tmpl.
NIX_DOTFILES_PROFILE = Path.home() / ".nix-profile"
NIX_DOTFILES_PROFILE_ELEMENT = "cli"
NIX_DOTFILES_INSTALLABLE = ".#cli"


class WorkTool(NamedTuple):
    repo: str
    path: Path


WORK_TOOL_REPOS = {
    "prod-errors": WorkTool(
        repo="git@github.com:riii111/prod-errors.git",
        path=Path.home() / "ghq" / "github.com" / "riii111" / "prod-errors",
    ),
}


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

    if command.startswith("python"):
        return None
    if command in {"zsh", "bash", "sh"}:
        return command
    return None


def detect_shell(path: Path) -> str | None:
    # A chezmoi template is classified by the file it renders to.
    name = path.name.removesuffix(".tmpl")
    suffix = Path(name).suffix
    # `.zsh` files in this repo are intentionally treated as zsh scripts
    # even if the shebang is omitted or differs.
    if suffix == ".zsh" or name.endswith(ZSH_STARTUP_FILES):
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
        # Templates are not shell syntax until chezmoi renders them, and shfmt -w
        # would rewrite their actions. See collect_shell_template_targets.
        if path.suffix == ".tmpl" or not path.is_file():
            continue
        shell = detect_shell(path)
        if shell is not None:
            targets.append((path, shell))
    return targets


def collect_shell_template_targets(paths: list[Path]) -> list[tuple[Path, str]]:
    targets: list[tuple[Path, str]] = []
    for path in paths:
        if path.suffix != ".tmpl" or not path.is_file():
            continue
        shell = detect_shell(path)
        if shell is not None:
            targets.append((path, shell))
    return targets


def collect_shell_targets(repo_root: Path) -> list[tuple[Path, str]]:
    paths = git_tracked_files(repo_root)
    return collect_detected_shell_targets(paths) + collect_shell_template_targets(paths)


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
    result: subprocess.CompletedProcess[str] | subprocess.CompletedProcess[bytes],
) -> None:
    print(f"{label}: failed (exit {result.returncode})", file=sys.stderr)
    for output in (result.stderr, result.stdout):
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        if output:
            print(output.rstrip(), file=sys.stderr)


def check_shell_syntax(shell_path: str, script: Path, label: str, cwd: Path) -> bool:
    result = subprocess.run(
        [shell_path, "-n", str(script)],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        # The shell echoes the offending line, which need not be valid UTF-8.
        errors="replace",
    )
    if result.returncode != 0:
        print_process_failure(f"shell syntax ({label})", result)
    return result.returncode == 0


def render_chezmoi_template(
    chezmoi: str,
    repo_root: Path,
    template: Path,
    data_file: Path,
    scratch: Path,
) -> subprocess.CompletedProcess[bytes]:
    # Only PATH and a throwaway HOME reach chezmoi, and its state goes to scratch
    # rather than next to the config file in the repo. That keeps the render from
    # reading or writing the machine's own chezmoi config, source and state.
    # The output stays raw bytes: text mode would turn CRLF into LF, hiding what
    # a shell rejects, and fail on bytes that are not UTF-8.
    return subprocess.run(
        [
            chezmoi,
            "--config",
            str(data_file),
            "--source",
            str(repo_root),
            "--persistent-state",
            str(scratch / "chezmoistate.boltdb"),
            "execute-template",
            "--file",
            str(template),
        ],
        cwd=repo_root,
        env={"PATH": os.environ.get("PATH", os.defpath), "HOME": str(scratch)},
        check=False,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def check_shell_template(repo_root: Path, template: Path, shell_path: str) -> list[str]:
    """Render a shell template for each machine type and syntax-check the result.

    Returns the failed checks, each named "<template> for <machine type>".
    """
    name = str(template.relative_to(repo_root))
    chezmoi = shutil.which("chezmoi")
    if chezmoi is None:
        print(
            f"shell syntax ({name}): chezmoi not found "
            "(run inside nix develop or install chezmoi)",
            file=sys.stderr,
        )
        return [name]

    failures: list[str] = []
    for machine in MACHINE_TYPES:
        label = f"{name} for {machine}"
        data_name = CHEZMOI_TEST_DATA_DIR / f"{machine}.toml"
        data_file = repo_root / data_name
        if not data_file.is_file():
            # chezmoi ignores a missing --config, and the render would then fail on
            # the first data key with a message that hides the real cause.
            print(f"template render ({label}): {data_name} not found", file=sys.stderr)
            failures.append(label)
            continue

        with tempfile.TemporaryDirectory() as scratch_dir:
            scratch = Path(scratch_dir)
            rendered = render_chezmoi_template(
                chezmoi, repo_root, template, data_file, scratch
            )
            if rendered.returncode != 0:
                print_process_failure(f"template render ({label})", rendered)
                failures.append(label)
                continue

            script = scratch / f"{template.name.removesuffix('.tmpl')}.{machine}"
            script.write_bytes(rendered.stdout)
            if not check_shell_syntax(shell_path, script, label, repo_root):
                failures.append(label)
    return failures


def command_test(_: argparse.Namespace) -> int:
    repo_root = resolve_repo_root()
    failures = 0

    ruff = shutil.which("ruff")
    if ruff is None:
        failures += 1
        print("ruff check: ruff not found", file=sys.stderr)
    else:
        ruff_result = run_command([ruff, "check", "."], repo_root)
        if ruff_result.returncode != 0:
            failures += 1
            print_process_failure("ruff check", ruff_result)

    test_result = run_command(
        ["python3", "-m", "unittest", "discover", "tests"], repo_root
    )
    if test_result.returncode != 0:
        failures += 1
        print_process_failure("python tests", test_result)

    bash = shutil.which("bash")
    for test_path in sorted((repo_root / "tests").glob("test-*.sh")):
        label = f"shell test ({test_path.relative_to(repo_root)})"
        if bash is None:
            failures += 1
            print(f"{label}: bash not found", file=sys.stderr)
            continue
        test_result = run_command([bash, str(test_path)], repo_root)
        if test_result.returncode != 0:
            failures += 1
            print_process_failure(label, test_result)

    lua = shutil.which("lua")
    if lua is None:
        failures += 1
        print(
            "lua tests: lua not found (run inside nix develop or install Lua 5.4)",
            file=sys.stderr,
        )
    else:
        lua_test_result = run_command(
            [lua, "private_dot_config/wezterm/tests/herdr_mode_test.lua"],
            repo_root,
        )
        if lua_test_result.returncode != 0:
            failures += 1
            print_process_failure("lua tests", lua_test_result)

    targets = collect_shell_targets(repo_root)
    if not targets:
        print("No shell targets found")
        return 1 if failures else 0

    print(f"Checking {len(targets)} shell targets")
    shell_failures: list[str] = []
    for path, shell in targets:
        name = str(path.relative_to(repo_root))
        shell_path = shutil.which(shell)
        if shell_path is None:
            shell_failures.append(name)
            print(f"shell syntax ({name}): {shell} not found", file=sys.stderr)
            continue

        if path.suffix == ".tmpl":
            shell_failures.extend(check_shell_template(repo_root, path, shell_path))
        elif not check_shell_syntax(shell_path, path, name, repo_root):
            shell_failures.append(name)

    if shell_failures:
        failures += 1
        print(
            "Shell syntax failed: " + ", ".join(shell_failures),
            file=sys.stderr,
        )
    else:
        print("Shell syntax OK")

    return 1 if failures else 0


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


def select_work_tools(name: str | None) -> list[tuple[str, WorkTool]]:
    if name is None:
        return list(WORK_TOOL_REPOS.items())
    try:
        return [(name, WORK_TOOL_REPOS[name])]
    except KeyError as exc:
        available = ", ".join(WORK_TOOL_REPOS)
        raise RuntimeError(
            f"unknown work tool: {name} (available: {available})"
        ) from exc


def command_work_tools_install(args: argparse.Namespace) -> int:
    failures = 0
    for name, tool in select_work_tools(args.name):
        if tool.path.exists():
            print(f"{name}: already installed")
            continue

        result = run_command(["ghq", "get", tool.repo], Path.home())
        if result.returncode != 0:
            print_process_failure(f"{name} install", result)
            failures += 1

    return 1 if failures else 0


def apply_work_tool(name: str, tool: WorkTool) -> int:
    path = tool.path
    if not path.exists():
        raise RuntimeError(
            f"{name} is not installed; run `dotctl work-tools install {name}`"
        )

    result = run_command(
        ["chezmoi", "-S", str(path), "apply", "--force", "--no-tty"],
        path,
    )
    if result.returncode != 0:
        print_process_failure(f"{name} apply", result)
        return 1
    return 0


def command_work_tools_apply(args: argparse.Namespace) -> int:
    failures = 0
    for name, tool in select_work_tools(args.name):
        failures += apply_work_tool(name, tool)
    return 1 if failures else 0


def command_work_tools_update(args: argparse.Namespace) -> int:
    failures = 0
    for name, tool in select_work_tools(args.name):
        path = tool.path
        if not path.exists():
            raise RuntimeError(
                f"{name} is not installed; run `dotctl work-tools install {name}`"
            )

        pull = run_command(["git", "pull", "--ff-only"], path)
        if pull.returncode != 0:
            print_process_failure(f"{name} update", pull)
            failures += 1
            continue
        failures += apply_work_tool(name, tool)

    return 1 if failures else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="dotctl")
    subparsers = parser.add_subparsers(dest="command", required=True)

    test_parser = subparsers.add_parser("test", help="run repo verification")
    test_parser.set_defaults(func=command_test)

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

    work_tools_parser = subparsers.add_parser(
        "work-tools",
        help="install/update private work tool layers",
    )
    work_tools_subparsers = work_tools_parser.add_subparsers(
        dest="work_tools_command",
        required=True,
    )

    work_tools_install_parser = work_tools_subparsers.add_parser(
        "install",
        help="clone private work tool repositories",
    )
    work_tools_install_parser.add_argument("name", nargs="?")
    work_tools_install_parser.set_defaults(func=command_work_tools_install)

    work_tools_apply_parser = work_tools_subparsers.add_parser(
        "apply",
        help="apply private work tool chezmoi layers",
    )
    work_tools_apply_parser.add_argument("name", nargs="?")
    work_tools_apply_parser.set_defaults(func=command_work_tools_apply)

    work_tools_update_parser = work_tools_subparsers.add_parser(
        "update",
        help="pull and apply private work tool repositories",
    )
    work_tools_update_parser.add_argument("name", nargs="?")
    work_tools_update_parser.set_defaults(func=command_work_tools_update)

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
