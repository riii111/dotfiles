#!/usr/bin/env python3
"""Quarantine a newer leftover SDK only when it breaks the installed CLT linker."""

import argparse
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
from pathlib import Path


DEVELOPER = Path("/Library/Developer/CommandLineTools")


def environment(sdk=None):
    result = dict(os.environ)
    for name in ("SDKROOT", "DEVELOPER_DIR", "TOOLCHAINS"):
        result.pop(name, None)
    result["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    result["DEVELOPER_DIR"] = str(DEVELOPER)
    if sdk is not None:
        result["SDKROOT"] = str(sdk)
    return result


def output(*arguments):
    return subprocess.check_output(arguments, env=environment()).decode().strip()


def compile_probe(sdk=None):
    with tempfile.TemporaryDirectory(prefix="sdk-link-probe-") as directory:
        source = Path(directory) / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        return subprocess.run(
            ["/usr/bin/cc", str(source), "-o", str(Path(directory) / "probe")],
            env=environment(sdk),
            text=True,
            capture_output=True,
        )


def sdk_major(path):
    version = json.loads((path / "SDKSettings.json").read_text())["Version"]
    return int(version.split(".")[0])


def repair_plan(sdk_directory, tools_major, selected):
    sdk_directory = sdk_directory.resolve(strict=True)
    preferred_link = sdk_directory / "MacOSX.sdk"
    if not preferred_link.is_symlink():
        raise RuntimeError("MacOSX.sdk must be the installer-managed symlink")
    preferred = preferred_link.resolve(strict=True)
    selected = selected.resolve(strict=True)
    if preferred.parent != sdk_directory or selected.parent != sdk_directory:
        raise RuntimeError("SDKs must be direct children of the CLT SDK directory")
    if sdk_major(preferred) != tools_major:
        raise RuntimeError("MacOSX.sdk does not match the installed CLT major version")
    if sdk_major(selected) <= tools_major or selected == preferred:
        raise RuntimeError("The failing SDK is not a newer leftover SDK")
    aliases = [
        path
        for path in sorted(sdk_directory.glob("MacOSX*.sdk"))
        if path.is_symlink() and path.resolve() == selected
    ]
    return preferred, [selected, *aliases]


def quarantine(paths, backup, verify):
    backup.mkdir(mode=0o700, parents=True, exist_ok=False)
    moved = []
    try:
        for original in paths:
            moved.append(original)
            original.rename(backup / original.name)
        verify()
    except BaseException:
        for original in reversed(moved):
            stored = backup / original.name
            if not stored.exists() and not stored.is_symlink():
                continue
            if original.exists() or original.is_symlink():
                raise RuntimeError(
                    f"Restore destination exists; backup retained at {backup}"
                )
            stored.rename(original)
        raise


def verify_default():
    output("/usr/bin/xcrun", "--kill-cache")
    result = compile_probe()
    if result.returncode:
        raise RuntimeError("Default SDK still fails to link:\n" + result.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="move the diagnosed SDK; requires root"
    )
    arguments = parser.parse_args()
    if sys.platform != "darwin":
        raise RuntimeError("This repair is only for macOS Command Line Tools")
    active = Path(
        subprocess.check_output(["/usr/bin/xcode-select", "--print-path"])
        .decode()
        .strip()
    )
    if active != DEVELOPER:
        raise RuntimeError("The active developer directory is not Command Line Tools")
    receipt = plistlib.loads(
        subprocess.check_output(
            [
                "/usr/sbin/pkgutil",
                "--pkg-info-plist",
                "com.apple.pkg.CLTools_Executables",
            ]
        )
    )
    tools_major = int(receipt["pkg-version"].split(".")[0])
    selected = Path(output("/usr/bin/xcrun", "--no-cache", "--show-sdk-path"))
    print(
        f"Installed CLT: {receipt['pkg-version']}\nDefault SDK: {selected}", flush=True
    )
    result = compile_probe()
    if result.returncode == 0:
        print("Default C link succeeds; no repair needed")
        return
    if (
        "unknown architecture" not in result.stderr
        or str(selected) not in result.stderr
    ):
        raise RuntimeError(
            "Link failure differs from the diagnosed SDK mismatch:\n" + result.stderr
        )
    preferred, paths = repair_plan(DEVELOPER / "SDKs", tools_major, selected)
    result = compile_probe(preferred)
    if result.returncode:
        raise RuntimeError(
            "The matching SDK also fails; no changes made:\n" + result.stderr
        )
    print(f"Matching SDK links successfully: {preferred}\nQuarantine candidates:")
    for path in paths:
        print(f"  {path}")
    if not arguments.apply:
        print(
            "Diagnosis only; no SDKs moved. Use --apply after reviewing the candidates."
        )
        return
    if os.geteuid() != 0:
        raise RuntimeError("--apply requires root; no SDKs moved")
    backup = DEVELOPER / "SDKs-disabled" / f"sdk-repair-{time.time_ns()}"
    print(f"Backup: {backup}", flush=True)
    try:
        quarantine(paths, backup, verify_default)
    except BaseException:
        output("/usr/bin/xcrun", "--kill-cache")
        raise
    print("Default C link succeeds. SDKs are retained in the backup above.")
    print("In your regular terminal, run: xcrun --kill-cache")


if __name__ == "__main__":
    try:
        main()
    except (
        OSError,
        RuntimeError,
        ValueError,
        KeyError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
