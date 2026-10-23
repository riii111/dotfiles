import json
import unittest
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli, launch_agent, pr_watch, review_notifier


HOME = Path("/Users/me")


class AgentPlistTest(unittest.TestCase):
    def test_each_tool_differs_only_in_its_own_fields(self):
        watch = launch_agent.agent_plist(pr_watch.agent(HOME), "me")
        notifier = launch_agent.agent_plist(review_notifier.agent(HOME), "me")

        own = {
            "Label",
            "ProgramArguments",
            "ProcessType",
            "StandardOutPath",
            "StandardErrorPath",
        }
        self.assertEqual(
            {key: value for key, value in watch.items() if key not in own},
            {key: value for key, value in notifier.items() if key not in own},
        )
        self.assertEqual(
            watch["ProgramArguments"], ["/Users/me/.local/bin/harnexus-task", "watch"]
        )
        self.assertEqual(
            notifier["ProgramArguments"],
            ["/Users/me/.local/bin/review-notifier", "run"],
        )
        self.assertEqual(
            [watch["ProcessType"], notifier["ProcessType"]],
            ["Background", "Interactive"],
        )
        self.assertEqual(
            pr_watch.agent(HOME).plist,
            HOME / "Library/LaunchAgents/io.github.riii111.pr-watch.plist",
        )


class WatchedPrsTest(unittest.TestCase):
    def test_reads_the_status_harnexus_task_prints(self):
        output = json.dumps(
            {
                "prs": [
                    {
                        "pr": "https://github.com/org/pay/pull/7",
                        "status": "watching",
                        "reason": None,
                        "pending": 2,
                        "awaitingAnswer": True,
                    },
                    {
                        "pr": "https://github.com/org/pay/pull/8",
                        "status": "stopped",
                        "reason": "worker thread is gone",
                        "pending": 0,
                        "awaitingAnswer": False,
                    },
                ]
            }
        )

        self.assertEqual(
            pr_watch.status_lines(output)[:-1],
            [
                "https://github.com/org/pay/pull/7 watching pending=2 awaiting answer",
                "https://github.com/org/pay/pull/8 stopped (worker thread is gone) pending=0",
            ],
        )


class SenderLineTest(unittest.TestCase):
    def test_names_the_sender_an_unreadable_record_or_how_to_register_one(self):
        self.assertEqual(
            pr_watch.status_lines(json.dumps({"sender": "chat-1", "prs": []})),
            ["sender: chat-1"],
        )
        self.assertEqual(
            pr_watch.sender_line({"sender": None, "senderError": "bad JSON"}),
            "sender: unreadable (bad JSON)",
        )
        self.assertIn(
            "harnexus-task watch --sender",
            pr_watch.sender_line({"sender": None}),
        )


class AgentActionTest(unittest.TestCase):
    def test_dispatches_the_shared_actions_to_the_tool_module(self):
        args = cli.build_parser().parse_args(["pr-watch", "logs", "-f"])
        with mock.patch.object(pr_watch, "logs", return_value=0) as logs:
            self.assertEqual(args.func(args), 0)
        logs.assert_called_once_with(Path.home(), follow=True)

        args = cli.build_parser().parse_args(["review-notifier", "stop"])
        with mock.patch.object(review_notifier, "stop", return_value=0) as stop:
            self.assertEqual(args.func(args), 0)
        stop.assert_called_once_with(Path.home())


if __name__ == "__main__":
    unittest.main()
