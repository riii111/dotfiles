import errno
import fcntl
import os
import pty
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(
    shutil.which("lefthook") and shutil.which("chezmoi"),
    "lefthook and chezmoi are required",
)
class TerminalQueriesTest(unittest.TestCase):
    def test_post_merge_applies_without_terminal_queries_and_reports_failures(self):
        for failure in (False, True):
            with (
                self.subTest(failure=failure),
                tempfile.TemporaryDirectory() as directory,
            ):
                home = Path(directory)
                source, destination, binaries = (
                    home / name for name in ("source", "destination", "bin")
                )
                for path in (source, destination, binaries):
                    path.mkdir()
                (source / "dot_probe").write_text("applied\n")
                (source / "run_after_probe.sh").write_text(
                    "#!/bin/sh\nprintf 'apply stdout\\n'\nprintf 'apply stderr\\n' >&2\n"
                    + ("exit 7\n" if failure else "")
                )
                config = home / "config.toml"
                config.write_text("")
                arguments = [
                    shutil.which("chezmoi"),
                    "--config",
                    str(config),
                    "--source",
                    str(source),
                    "--destination",
                    str(destination),
                    "--persistent-state",
                    str(home / "state"),
                ]
                wrapper = binaries / "chezmoi"
                wrapper.write_text(
                    "#!/bin/sh\nexec " + shlex.join(arguments) + ' "$@"\n'
                )
                wrapper.chmod(0o755)
                shutil.copyfile(ROOT / "lefthook.yml", home / "lefthook.yml")
                env = {
                    "HOME": directory,
                    "PATH": str(binaries)
                    + os.pathsep
                    + os.environ.get("PATH", os.defpath),
                    "TERM": "xterm-256color",
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_CONFIG_GLOBAL": os.devnull,
                }
                subprocess.run(["git", "init", "-q", directory], env=env, check=True)
                master, slave = pty.openpty()
                fcntl.ioctl(
                    slave, termios.TIOCSWINSZ, struct.pack("HHHH", 26, 100, 0, 0)
                )
                process = subprocess.Popen(
                    [shutil.which("lefthook"), "run", "post-merge"],
                    cwd=home,
                    env=env,
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    start_new_session=True,
                )
                os.close(slave)
                output = b""
                try:
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                chunk = os.read(master, 65536)
                            except OSError as error:
                                if error.errno == errno.EIO:
                                    break
                                raise
                            if not chunk:
                                break
                            output += chunk
                        elif process.poll() is not None:
                            break
                    process.wait(timeout=1)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)
                    os.close(master)
                self.assertEqual(process.returncode == 0, not failure, output)
                self.assertEqual((destination / ".probe").read_text(), "applied\n")
                self.assertIn(b"apply stdout", output)
                self.assertIn(b"apply stderr", output)
                self.assertNotIn(b"\x1b]11;?", output)
                self.assertNotIn(b"\x1b[6n", output)
