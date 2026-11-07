import os
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(
    shutil.which("zsh") and shutil.which("chezmoi"), "zsh and chezmoi are required"
)
class RepositoryWidgetTest(unittest.TestCase):
    def test_selection_and_cancellation_preserve_the_editing_line(self):
        # The widgets do not depend on the machine type. Selecting a repository
        # changes the directory; a cancelled branch switch must still restore the line.
        for key, cancel in (("repository", False), ("branch", True)):
            with (
                self.subTest(key=key, cancel=cancel),
                tempfile.TemporaryDirectory() as directory,
            ):
                home = Path(directory).resolve()
                destination = home / "ghq/repo with spaces"
                destination.mkdir(parents=True)
                env = {
                    "HOME": str(home),
                    "ZDOTDIR": str(home),
                    "PATH": os.environ.get("PATH", os.defpath),
                    "TERM": "xterm",
                    "CANCEL": str(int(cancel)),
                }
                rendered = subprocess.check_output(
                    [
                        "chezmoi",
                        "--config",
                        str(ROOT / "tests/chezmoi/personal.toml"),
                        "--source",
                        str(ROOT),
                        "--persistent-state",
                        str(home / "state"),
                        "execute-template",
                        "--file",
                        str(ROOT / "dot_zshrc.tmpl"),
                    ],
                    env=env,
                    text=True,
                )
                (home / ".zshenv").write_text((ROOT / "dot_zshenv").read_text())
                (home / ".zshrc").write_text(
                    rendered
                    + """
PROMPT='WIDGET-READY> '
ghq() { if [[ $1 == root ]]; then print -r -- "$HOME/ghq"; else print -r -- 'repo with spaces'; fi }
fzf() { [[ $CANCEL == 1 ]] && return 130; print -r -- 'repo with spaces' }
git() { print -r -- "$*" > "$HOME/git-call"; [[ $CANCEL == 0 ]] }
_capture() { print -r -- "$BUFFER|$CURSOR|$PWD" > "$HOME/result"; }
zle -N _capture
bindkey '^X' _capture
bindkey '^Y' backward-char
"""
                )
                master, slave = pty.openpty()
                process = subprocess.Popen(
                    [shutil.which("zsh"), "-d", "-i"],
                    cwd=home,
                    env=env,
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    start_new_session=True,
                )
                os.close(slave)
                try:
                    output = b""
                    deadline = time.monotonic() + 20
                    while (
                        b"WIDGET-READY> " not in output and time.monotonic() < deadline
                    ):
                        if select.select([master], [], [], 0.1)[0]:
                            output += os.read(master, 65536)
                    self.assertIn(b"WIDGET-READY> ", output)
                    selection_key = b"\x07" if key == "repository" else b"\x02"
                    # Ctrl+; can reach zsh from the terminal's multiplexer prefix.
                    # Exercise it both before the first text input and while editing.
                    prefix = b"\x1b[59;5u"
                    os.write(
                        master,
                        prefix + b": abcdef\x19\x19" + prefix + selection_key + b"\x18",
                    )
                    while (
                        not (home / "result").exists() and time.monotonic() < deadline
                    ):
                        if select.select([master], [], [], 0.1)[0]:
                            output += os.read(master, 65536)
                    self.assertTrue(
                        (home / "result").exists(), output.decode(errors="replace")
                    )
                    expected_cwd = (
                        destination if key == "repository" and not cancel else home
                    )
                    self.assertEqual(
                        (home / "result").read_text().strip(),
                        f": abcdef|6|{expected_cwd}",
                    )
                    if key == "branch":
                        self.assertEqual((home / "git-call").read_text().strip(), "swf")
                finally:
                    process.kill()
                    process.wait(timeout=5)
                    os.close(master)
