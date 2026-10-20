import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli, review_notifier


class AgentPlistTest(unittest.TestCase):
    def test_plist_runs_the_installed_binary_without_the_shell_environment(self):
        home = Path("/Users/me")
        plist = review_notifier.agent_plist(home, "me")
        self.assertEqual(
            plist["ProgramArguments"], ["/Users/me/.local/bin/review-notifier", "run"]
        )
        self.assertEqual(plist["LimitLoadToSessionType"], "Aqua")
        self.assertEqual(plist["KeepAlive"], {"SuccessfulExit": False})
        path = plist["EnvironmentVariables"]["PATH"].split(":")
        self.assertEqual(path[0], "/Users/me/.nix-profile/bin")
        self.assertIn("/etc/profiles/per-user/me/bin", path)
        self.assertIn("/usr/bin", path)
        self.assertEqual(
            plist["StandardErrorPath"], "/Users/me/Library/Logs/review-notifier.log"
        )
        # Serializable as a launchd property list.
        plistlib.dumps(plist)


class InstallTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)

    def test_install_stops_without_a_config(self):
        with mock.patch.object(review_notifier, "run") as run:
            self.assertEqual(review_notifier.install(Path("/repo"), self.home, "me"), 1)
        run.assert_not_called()

    def test_install_does_not_load_the_agent_when_check_fails(self):
        config = review_notifier.config_path(self.home)
        config.parent.mkdir(parents=True)
        config.write_text("{}", encoding="utf-8")
        with (
            mock.patch.object(review_notifier, "build", return_value=0),
            mock.patch.object(review_notifier, "run", return_value=1) as run,
            mock.patch.object(review_notifier, "start") as start,
        ):
            self.assertEqual(review_notifier.install(Path("/repo"), self.home, "me"), 1)
        run.assert_called_once_with(
            [str(review_notifier.binary_path(self.home)), "check"]
        )
        start.assert_not_called()
        self.assertFalse(review_notifier.plist_path(self.home).exists())

    def test_install_writes_the_plist_and_starts(self):
        config = review_notifier.config_path(self.home)
        config.parent.mkdir(parents=True)
        config.write_text("{}", encoding="utf-8")
        with (
            mock.patch.object(review_notifier, "build", return_value=0),
            mock.patch.object(review_notifier, "run", return_value=0),
            mock.patch.object(review_notifier, "stop", return_value=0),
            mock.patch.object(review_notifier, "start", return_value=0) as start,
        ):
            self.assertEqual(review_notifier.install(Path("/repo"), self.home, "me"), 0)
        start.assert_called_once_with(self.home)
        with review_notifier.plist_path(self.home).open("rb") as handle:
            self.assertEqual(plistlib.load(handle)["Label"], review_notifier.LABEL)


class ParserTest(unittest.TestCase):
    def test_review_notifier_subcommands(self):
        parser = cli.build_parser()
        for name in ("install", "uninstall", "start", "stop", "status"):
            args = parser.parse_args(["review-notifier", name])
            self.assertEqual(args.review_notifier_command, name)
        args = parser.parse_args(["review-notifier", "logs", "-f"])
        self.assertTrue(args.follow)


if __name__ == "__main__":
    unittest.main()
