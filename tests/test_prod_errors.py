# ruff: noqa: E402

import argparse
import contextlib
import io
import json
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "bin" / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

from prod_errors.cli import build_parser
from prod_errors.ansi import display_width, pad_left, pad_right, trunc
from prod_errors.commands import cmd_hotspots, cmd_trace
from prod_errors.logic import (
    build_hotspot_data,
    build_service_summary_data,
    windowed_counts,
)
from prod_errors.trace import _extract_context_from_object


def make_group(
    group_id,
    status,
    message,
    count,
    first_seen,
    last_seen,
    service,
    timed_counts=None,
):
    item = {
        "group": {"groupId": group_id, "resolutionStatus": status},
        "representative": {"message": message},
        "count": str(count),
        "firstSeenTime": first_seen,
        "lastSeenTime": last_seen,
        "affectedServices": [{"service": service}] if service else [],
    }
    if timed_counts is not None:
        item["timedCounts"] = timed_counts
    return item


def make_trace_log(timestamp, severity, message, logger="app", **payload):
    json_payload = {"message": message, "logger": logger}
    json_payload.update(payload)
    return {
        "timestamp": timestamp,
        "severity": severity,
        "jsonPayload": json_payload,
    }


class ProdErrorsLogicTest(unittest.TestCase):
    def test_windowed_counts_uses_timed_counts_since_boundary(self):
        item = make_group(
            "g1",
            "OPEN",
            "FooError: boom",
            10,
            "2026-04-01T00:00:00.000000Z",
            "2026-04-04T00:00:00.000000Z",
            "svc-a",
            timed_counts=[
                {
                    "count": "3",
                    "startTime": "2026-04-01T00:00:00.000000Z",
                    "endTime": "2026-04-02T00:00:00.000000Z",
                },
                {
                    "count": "2",
                    "startTime": "2026-04-03T00:00:00.000000Z",
                    "endTime": "2026-04-04T00:00:00.000000Z",
                },
            ],
        )

        count, active_days, first_seen, last_seen = windowed_counts(
            item, since="2026-04-02T12:00:00.000000Z"
        )

        self.assertEqual(count, 2)
        self.assertEqual(active_days, 1)
        self.assertEqual(first_seen, "2026-04-03T00:00:00.000000Z")
        self.assertEqual(last_seen, "2026-04-04T00:00:00.000000Z")

    def test_build_hotspot_data_sorts_and_rewrites_related_rank(self):
        filtered = [
            make_group(
                "g1",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-04T00:00:00.000000Z",
                "svc-a",
                timed_counts=[
                    {
                        "count": "2",
                        "startTime": "2026-04-03T00:00:00.000000Z",
                        "endTime": "2026-04-04T00:00:00.000000Z",
                    }
                ],
            ),
            make_group(
                "g2",
                "RESOLVED",
                "  at pkg.Class.method",
                4,
                "2026-04-02T00:00:00.000000Z",
                "2026-04-03T00:00:00.000000Z",
                "svc-a",
                timed_counts=[
                    {
                        "count": "4",
                        "startTime": "2026-04-02T00:00:00.000000Z",
                        "endTime": "2026-04-03T00:00:00.000000Z",
                    }
                ],
            ),
        ]

        items = build_hotspot_data(filtered, since="2026-04-02T12:00:00.000000Z")

        self.assertEqual([item["groupId"] for item in items], ["g2", "g1"])
        self.assertEqual(items[0]["relatedTo"], 2)
        self.assertIsNone(items[1]["relatedTo"])
        self.assertEqual(items[0]["activeBuckets"], 1)

    def test_build_service_summary_data_aggregates_by_service(self):
        filtered = [
            make_group(
                "g1",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
            ),
            make_group(
                "g2",
                "RESOLVED",
                "BarError: boom",
                3,
                "2026-04-02T00:00:00.000000Z",
                "2026-04-04T00:00:00.000000Z",
                "svc-a",
            ),
            make_group(
                "g3",
                "OPEN",
                "BazError: boom",
                7,
                "2026-04-03T00:00:00.000000Z",
                "2026-04-06T00:00:00.000000Z",
                "svc-b",
            ),
        ]

        summary = build_service_summary_data(
            filtered, since="2026-04-02T12:00:00.000000Z"
        )

        self.assertEqual(summary[0]["service"], "svc-a")
        self.assertEqual(summary[0]["groupCount"], 2)
        self.assertEqual(summary[0]["totalCount"], 8)
        self.assertEqual(summary[0]["newCount"], 0)
        self.assertEqual(summary[0]["regressedCount"], 2)


class ProdErrorsTraceHelpersTest(unittest.TestCase):
    def test_extract_context_from_object_reads_nested_aliases_and_strings(self):
        context = {}

        _extract_context_from_object(
            {
                "request": {
                    "headers": {
                        "x-tenant-id": "tenant-a",
                        "x-user-account-id": "ua-1",
                    }
                },
                "detail": 'actor="userId: user-9"',
            },
            context,
        )

        self.assertEqual(context["tenantId"], "tenant-a")
        self.assertEqual(context["userAccountId"], "ua-1")
        self.assertEqual(context["userId"], "user-9")

    def test_extract_context_from_object_stops_at_max_depth(self):
        nested = "tenantId=too-deep"
        for _ in range(20):
            nested = {"child": nested}

        context = {}

        _extract_context_from_object(nested, context)

        self.assertEqual(context, {})


class ProdErrorsAnsiTest(unittest.TestCase):
    def test_display_width_counts_wide_chars(self):
        self.assertEqual(display_width("abc"), 3)
        self.assertEqual(display_width("ログ"), 4)

    def test_padding_uses_display_width(self):
        self.assertEqual(pad_right("ログ", 6), "ログ  ")
        self.assertEqual(pad_left("12", 4), "  12")

    def test_trunc_uses_display_width(self):
        self.assertEqual(trunc("ログイン時にエラー", 8), "ログイ…")


class ProdErrorsCliTest(unittest.TestCase):
    def test_build_parser_supports_hotspots(self):
        parser = build_parser()

        args = parser.parse_args(["--project", "demo", "hotspots", "--period", "7d"])

        self.assertEqual(args.command, "hotspots")
        self.assertEqual(args.project, "demo")
        self.assertEqual(args.period, "7d")

    def test_hotspots_since_help_mentions_approximate_buckets(self):
        parser = build_parser()

        hotspots_action = next(
            action
            for action in parser._actions
            if isinstance(action, argparse._SubParsersAction)
        )
        hotspots_parser = hotspots_action.choices["hotspots"]
        since_action = next(
            action for action in hotspots_parser._actions if action.dest == "since"
        )

        self.assertIn("overlapping buckets are counted in full", since_action.help)


class ProdErrorsCommandTest(unittest.TestCase):
    _DEFAULT_GROUPS = [
        make_group(
            "g-trace",
            "OPEN",
            "FooError: boom",
            5,
            "2026-04-01T00:00:00.000000Z",
            "2026-04-05T00:00:00.000000Z",
            "svc-a",
        )
    ]
    _DEFAULT_EVENTS = {
        "errorEvents": [
            {
                "eventTime": "2026-04-05T00:00:00.000000Z",
                "serviceContext": {"service": "svc-a"},
            }
        ]
    }
    _DEFAULT_CLOUD_LOG = [
        {
            "timestamp": "2026-04-05T00:00:00.000000Z",
            "severity": "ERROR",
            "resource": {"labels": {"service_name": "svc-a"}},
            "jsonPayload": {
                "message": "FooError: boom",
                "logger": "app",
                "trace_id": "trace-123",
            },
        }
    ]

    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch("prod_errors.commands.api_get_all_pages")
    def test_cmd_hotspots_json_filters_status_and_uses_buckets(
        self, mock_api_get_all_pages, _mock_get_token
    ):
        mock_api_get_all_pages.return_value = [
            make_group(
                "g-open",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
                timed_counts=[
                    {
                        "count": "2",
                        "startTime": "2026-04-03T00:00:00.000000Z",
                        "endTime": "2026-04-04T00:00:00.000000Z",
                    }
                ],
            ),
            make_group(
                "g-resolved",
                "RESOLVED",
                "BarError: boom",
                8,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-06T00:00:00.000000Z",
                "svc-b",
                timed_counts=[
                    {
                        "count": "8",
                        "startTime": "2026-04-02T00:00:00.000000Z",
                        "endTime": "2026-04-03T00:00:00.000000Z",
                    }
                ],
            ),
        ]

        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            since="2026-04-02T12:00:00Z",
            period="30d",
            limit=20,
            json=True,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["total"], 1)
        self.assertEqual(payload["errors"][0]["groupId"], "g-open")
        self.assertEqual(payload["errors"][0]["activeBuckets"], 1)

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    def test_cmd_trace_shows_matched_logs_without_cloud_trace_id(
        self,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = [
            make_group(
                "g-trace",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
            )
        ]
        mock_api_get.return_value = {
            "errorEvents": [
                {
                    "eventTime": "2026-04-05T00:00:00.000000Z",
                    "serviceContext": {"service": "svc-a"},
                }
            ]
        }
        mock_logging_read.return_value = [
            {
                "timestamp": "2026-04-05T00:00:00.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "textPayload": "FooError: boom",
            }
        ]

        args = argparse.Namespace(
            project="demo",
            group_id="g-trace",
            json=False,
            freshness="30d",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(args)

        output = stdout.getvalue()
        self.assertIn("## Error Group: g-trace", output)
        self.assertIn("### Matched Error Logs", output)
        self.assertIn("Cloud Trace ID: (not found)", output)
        self.assertIn("Request-lifecycle lookup is unavailable", output)
        self.assertNotIn("### Recent Events", output)
        self.assertNotIn("### Cloud Logging Lookup", output)

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read", return_value=[])
    def test_cmd_trace_shows_recent_events_only_as_fallback_when_logs_not_found(
        self,
        _mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = [
            make_group(
                "g-trace",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
            )
        ]
        mock_api_get.return_value = {
            "errorEvents": [
                {
                    "eventTime": "2026-04-05T00:00:00.000000Z",
                    "serviceContext": {"service": "svc-a"},
                }
            ]
        }

        args = argparse.Namespace(
            project="demo",
            group_id="g-trace",
            json=False,
            freshness="30d",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(args)

        output = stdout.getvalue()
        self.assertIn("No matching logs in Cloud Logging", output)
        self.assertIn("### Recent Events (1)", output)
        self.assertNotIn("### Matched Error Logs", output)

    def test_cmd_trace_json_includes_lifecycle_and_retry_check(self):
        payload = self._run_trace_json(
            [
                self._DEFAULT_CLOUD_LOG,
                [
                    make_trace_log(
                        "2026-04-05T00:00:02.000000Z",
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-a",
                                "x-user-account-id": "ua-1",
                            }
                        },
                    ),
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-a",
                                "x-user-account-id": "ua-1",
                            }
                        },
                    ),
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:03.000000Z",
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-a",
                                "x-user-account-id": "ua-1",
                            }
                        },
                    )
                ],
            ]
        )

        self.assertEqual(payload["groupId"], "g-trace")
        self.assertEqual(payload["cloudLogging"]["traceId"], "trace-123")
        self.assertEqual(len(payload["lifecycle"]["entries"]), 2)
        self.assertEqual(payload["retryCheck"]["sourceContext"]["tenantId"], "tenant-a")
        self.assertEqual(
            payload["retryCheck"]["sourceContext"]["userAccountId"], "ua-1"
        )
        self.assertEqual(payload["retryCheck"]["verdict"], "recovered_same_caller")

    def test_cmd_trace_json_marks_same_tenant_recovery(self):
        payload = self._run_trace_json(
            [
                self._DEFAULT_CLOUD_LOG,
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-a",
                                "x-user-account-id": "ua-1",
                            }
                        },
                    )
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:03.000000Z",
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-a",
                                "x-user-account-id": "ua-2",
                            }
                        },
                    )
                ],
            ]
        )

        self.assertEqual(payload["retryCheck"]["sameTenantSuccessCount"], 1)
        self.assertEqual(payload["retryCheck"]["sameCallerSuccessCount"], 0)
        self.assertEqual(payload["retryCheck"]["verdict"], "recovered_same_tenant")

    def test_cmd_trace_json_marks_endpoint_only_recovery_when_context_differs(
        self,
    ):
        payload = self._run_trace_json(
            [
                self._DEFAULT_CLOUD_LOG,
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-a",
                                "x-user-account-id": "ua-1",
                            }
                        },
                    )
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:03.000000Z",
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                        request={
                            "headers": {
                                "x-tenant-id": "tenant-b",
                                "x-user-account-id": "ua-9",
                            }
                        },
                    )
                ],
            ]
        )

        self.assertEqual(payload["retryCheck"]["sameTenantSuccessCount"], 0)
        self.assertEqual(payload["retryCheck"]["sameCallerSuccessCount"], 0)
        self.assertEqual(payload["retryCheck"]["verdict"], "recovered_endpoint_only")
        self.assertEqual(
            payload["retryCheck"]["detail"],
            "Subsequent success found on the same endpoint, but tenant/caller match was not confirmed.",
        )

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    def test_cmd_trace_output_marks_endpoint_only_recovery_when_context_differs(
        self,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.side_effect = [
            self._DEFAULT_CLOUD_LOG,
            [
                make_trace_log(
                    "2026-04-05T00:00:01.000000Z",
                    "ERROR",
                    "500 Internal Server Error: GET - /foo in 10ms",
                    request={
                        "headers": {
                            "x-tenant-id": "tenant-a",
                            "x-user-account-id": "ua-1",
                        }
                    },
                )
            ],
            [
                make_trace_log(
                    "2026-04-05T00:00:03.000000Z",
                    "INFO",
                    "200 OK: GET - /foo in 20ms",
                    logger="access",
                    request={
                        "headers": {
                            "x-tenant-id": "tenant-b",
                            "x-user-account-id": "ua-9",
                        }
                    },
                )
            ],
        ]

        args = argparse.Namespace(
            project="demo",
            group_id="g-trace",
            json=False,
            freshness="30d",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(args)

        output = stdout.getvalue()
        self.assertIn("Recovered (endpoint only)", output)
        self.assertIn("tenant/caller match was not confirmed", output)

    def test_cmd_trace_json_marks_not_recovered_when_only_failures_follow(self):
        payload = self._run_trace_json(
            [
                self._DEFAULT_CLOUD_LOG,
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                        request={"headers": {"x-tenant-id": "tenant-a"}},
                    )
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:03.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 20ms",
                        request={"headers": {"x-tenant-id": "tenant-a"}},
                    )
                ],
            ]
        )

        self.assertEqual(payload["retryCheck"]["successCount"], 0)
        self.assertEqual(payload["retryCheck"]["failureCount"], 1)
        self.assertEqual(payload["retryCheck"]["verdict"], "not_recovered")

    def test_cmd_trace_json_marks_no_subsequent_requests_when_retry_logs_are_empty(
        self,
    ):
        payload = self._run_trace_json(
            [
                self._DEFAULT_CLOUD_LOG,
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                    )
                ],
                [],
            ]
        )
        self.assertEqual(payload["retryCheck"]["verdict"], "no_subsequent_requests")
        self.assertEqual(
            payload["retryCheck"]["detail"],
            "No subsequent requests were found on the same endpoint after the error.",
        )

    def test_cmd_trace_json_falls_back_to_endpoint_only_without_context(self):
        payload = self._run_trace_json(
            [
                self._DEFAULT_CLOUD_LOG,
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                    )
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:03.000000Z",
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                    )
                ],
            ]
        )
        self.assertEqual(payload["retryCheck"]["sourceContext"], {})
        self.assertEqual(payload["retryCheck"]["verdict"], "recovered_endpoint_only")

    def _run_trace_json(self, logging_side_effect):
        with (
            mock.patch("prod_errors.trace.get_token", return_value="token"),
            mock.patch("prod_errors.trace.api_get", return_value=self._DEFAULT_EVENTS),
            mock.patch(
                "prod_errors.trace.api_get_all_pages",
                return_value=self._DEFAULT_GROUPS,
            ),
            mock.patch("prod_errors.trace.logging_read") as mock_logging,
        ):
            mock_logging.side_effect = logging_side_effect
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                cmd_trace(
                    argparse.Namespace(
                        project="demo",
                        group_id="g-trace",
                        json=True,
                        freshness="30d",
                    )
                )
            return json.loads(stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
