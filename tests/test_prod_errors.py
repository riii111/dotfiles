# ruff: noqa: E402

import argparse
import contextlib
import io
import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "bin" / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

from prod_errors.cli import build_parser
from prod_errors.ansi import display_width, pad_left, pad_right, trunc
from prod_errors.client import extract_trace_id, logging_list_all
from prod_errors.correlation import parse_window
from prod_errors.commands import (
    _find_prior_occurrences,
    _resolve_hotspot_window,
    cmd_hotspots,
    cmd_summary,
    cmd_trace,
)
from prod_errors.fingerprint import extract_request_fingerprint
from prod_errors.logic import (
    aggregate_hotspot_logs,
    build_hotspot_analysis,
    build_service_summary_data,
)
from prod_errors.timefmt import (
    format_jst_timestamp,
    parse_timestamp,
    format_relative_age,
    format_summary_last_seen,
)
from prod_errors.trace import (
    _collect_endpoint_candidates,
    _collect_logger_clues,
    _collect_message_variants,
    _coerce_http_status,
    _extract_service_name,
    _extract_context_from_object,
    _extract_http_request_info,
    _find_first_trace_entry,
    _find_first_trace_id,
    _normalize_endpoint_value,
)


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


def make_request_log(
    timestamp,
    status,
    request_id,
    file_ids,
    trace_id=None,
    endpoint="/foo",
    service="svc-a",
):
    return {
        "timestamp": timestamp,
        "severity": "INFO" if status < 500 else "ERROR",
        "resource": {"labels": {"service_name": service}},
        "trace": f"projects/demo/traces/{trace_id}" if trace_id else "",
        "jsonPayload": {
            "message": f"{status} request: POST - {endpoint} in 20ms",
            "logger": "access",
            "requestBody": {
                "id": request_id,
                "files": [{"id": file_id} for file_id in file_ids],
            },
            "headers": {
                "x-tenant-id": "tenant-a",
                "x-user-account-id": "ua-1",
            },
        },
    }


def make_access_log(timestamp, status, endpoint="/foo", trace_id=None, service="svc-a"):
    return {
        "timestamp": timestamp,
        "severity": "INFO" if status < 500 else "ERROR",
        "resource": {"labels": {"service_name": service}},
        "trace": f"projects/demo/traces/{trace_id}" if trace_id else "",
        "jsonPayload": {
            "message": f"{status} request: POST - {endpoint} in 20ms",
            "logger": "access",
        },
    }


def make_request_info_log(
    timestamp,
    request_id,
    file_ids,
    endpoint="/foo",
    trace_id=None,
    service="svc-a",
):
    return {
        "timestamp": timestamp,
        "severity": "INFO",
        "resource": {"labels": {"service_name": service}},
        "trace": f"projects/demo/traces/{trace_id}" if trace_id else "",
        "jsonPayload": {
            "message": f"Request Information POST {endpoint}",
            "logger": "app",
            "requestBody": {
                "id": request_id,
                "files": [{"id": file_id} for file_id in file_ids],
            },
        },
    }


def make_hotspot_log(timestamp, group_id, message, service="svc-a"):
    return {
        "timestamp": timestamp,
        "errorGroups": [{"id": group_id}],
        "resource": {"labels": {"service_name": service}},
        "jsonPayload": {"message": message},
    }


class ProdErrorsLogicTest(unittest.TestCase):
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

    def test_build_hotspot_analysis_summarizes_new_and_recurring_groups(self):
        entries = [
            make_hotspot_log(
                "2026-04-01T01:00:00.000000Z", "g-new", "FooError: new", "svc-a"
            ),
            make_hotspot_log(
                "2026-04-01T12:00:00.000000Z", "g-rec", "BarError: recurring", "svc-b"
            ),
            make_hotspot_log(
                "2026-04-02T01:00:00.000000Z", "g-rec", "BarError: recurring", "svc-b"
            ),
        ]
        aggregated = aggregate_hotspot_logs(
            entries,
            since="2026-04-01T00:00:00.000000Z",
            until="2026-04-03T00:00:00.000000Z",
            bucket="1d",
        )
        metadata = {
            "g-new": make_group(
                "g-new",
                "OPEN",
                "FooError: new",
                1,
                "2026-04-01T01:00:00.000000Z",
                "2026-04-01T01:00:00.000000Z",
                "svc-a",
            ),
            "g-rec": make_group(
                "g-rec",
                "RESOLVED",
                "BarError: recurring",
                2,
                "2026-03-20T01:00:00.000000Z",
                "2026-04-02T01:00:00.000000Z",
                "svc-b",
            ),
        }

        analysis = build_hotspot_analysis(
            aggregated,
            metadata,
            prior_occurrences={"g-new": False, "g-rec": True},
            since="2026-04-01T00:00:00.000000Z",
            until="2026-04-03T00:00:00.000000Z",
            bucket="1d",
        )

        self.assertEqual(analysis["summary"]["totalGroups"], 2)
        self.assertEqual(analysis["summary"]["newGroups"], 1)
        self.assertEqual(analysis["summary"]["recurringGroups"], 1)
        self.assertEqual(analysis["summary"]["eventCount"], 3)
        self.assertEqual(analysis["buckets"][0]["activeGroups"], 2)
        self.assertEqual(analysis["buckets"][0]["activeNewGroups"], 1)
        self.assertEqual(analysis["buckets"][0]["activeRecurringGroups"], 1)
        self.assertEqual(analysis["buckets"][0]["newGroups"], 1)
        self.assertEqual(analysis["buckets"][0]["recurringGroups"], 1)
        self.assertEqual(analysis["buckets"][1]["activeGroups"], 1)
        self.assertEqual(analysis["buckets"][1]["activeRecurringGroups"], 1)
        self.assertEqual(analysis["buckets"][1]["recurringGroups"], 0)
        self.assertEqual(analysis["errors"][0]["groupId"], "g-rec")
        self.assertTrue(analysis["errors"][0]["isRecurringInRange"])
        self.assertTrue(analysis["errors"][1]["isNewInRange"])


class ProdErrorsTraceHelpersTest(unittest.TestCase):
    def test_parse_window_supports_seconds_minutes_and_hours(self):
        self.assertEqual(parse_window("30s").total_seconds(), 30)
        self.assertEqual(parse_window("5m").total_seconds(), 300)
        self.assertEqual(parse_window("1h").total_seconds(), 3600)

    def test_extract_request_fingerprint_reads_request_body_ids_and_caller(self):
        entry = make_request_log(
            "2026-04-05T00:00:00.000000Z",
            200,
            "20337152-1406-4727-9e11-a67722f22be6",
            [
                "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
                "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb",
            ],
        )

        fingerprint = extract_request_fingerprint(entry)

        self.assertEqual(
            fingerprint["requestId"], "20337152-1406-4727-9e11-a67722f22be6"
        )
        self.assertEqual(
            fingerprint["fileIds"],
            [
                "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
                "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb",
            ],
        )
        self.assertEqual(fingerprint["caller"]["tenantId"], "tenant-a")
        self.assertIn("request_id=20337152...", fingerprint["summary"])

    def test_extract_request_fingerprint_reads_message_ids_without_file_id_leak(self):
        entry = make_trace_log(
            "2026-04-05T00:00:00.000000Z",
            "INFO",
            (
                "Request Information POST /foo "
                "requestBody.id=20337152-1406-4727-9e11-a67722f22be6 "
                "files[].id=aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
            ),
        )

        fingerprint = extract_request_fingerprint(entry)

        self.assertEqual(
            fingerprint["requestId"], "20337152-1406-4727-9e11-a67722f22be6"
        )
        self.assertEqual(
            fingerprint["fileIds"], ["aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"]
        )

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

    def test_extract_context_from_object_reads_x_app_headers(self):
        context = {}

        _extract_context_from_object(
            {
                "headers": {
                    "X-App-Tenant-Id": "tenant-a",
                    "X-App-Account-Id": "account-a",
                    "X-App-User-Id": "user-a",
                }
            },
            context,
        )

        self.assertEqual(context["tenantId"], "tenant-a")
        self.assertEqual(context["userAccountId"], "account-a")
        self.assertEqual(context["userId"], "user-a")

    def test_extract_context_from_object_stops_at_max_depth(self):
        nested = "tenantId=too-deep"
        for _ in range(20):
            nested = {"child": nested}

        context = {}

        _extract_context_from_object(nested, context)

        self.assertEqual(context, {})

    def test_normalize_endpoint_value_handles_full_url_and_query(self):
        self.assertEqual(
            _normalize_endpoint_value("https://example.com/foo/bar?debug=true"),
            "/foo/bar?debug=true",
        )

    def test_normalize_endpoint_value_handles_plain_path_and_empty_values(self):
        self.assertEqual(_normalize_endpoint_value("/foo/bar"), "/foo/bar")
        self.assertIsNone(_normalize_endpoint_value(""))
        self.assertIsNone(_normalize_endpoint_value(None))

    def test_coerce_http_status_rejects_invalid_values(self):
        self.assertEqual(_coerce_http_status("200"), 200)
        self.assertIsNone(_coerce_http_status(None))
        self.assertIsNone(_coerce_http_status(""))
        self.assertIsNone(_coerce_http_status(True))
        self.assertIsNone(_coerce_http_status(0))
        self.assertIsNone(_coerce_http_status(-1))

    def test_extract_http_request_info_prefers_access_log_regex(self):
        entry = make_trace_log(
            "2026-04-05T00:00:01.000000Z",
            "ERROR",
            "500 Internal Server Error: GET - /foo in 10ms",
            request={"path": "/ignored", "status": 200},
        )

        self.assertEqual(
            _extract_http_request_info(entry),
            {"httpStatus": 500, "endpoint": "/foo"},
        )

    def test_extract_http_request_info_reads_request_information_message(self):
        entry = make_trace_log(
            "2026-04-05T00:00:01.000000Z",
            "INFO",
            "Request Information POST /api/smart-hanko",
        )

        self.assertEqual(
            _extract_http_request_info(entry),
            {"httpStatus": None, "endpoint": "/api/smart-hanko"},
        )

    def test_extract_http_request_info_reads_http_request_fields(self):
        entry = {
            "timestamp": "2026-04-05T00:00:00.000000Z",
            "severity": "ERROR",
            "httpRequest": {
                "requestUrl": "https://example.com/foo/bar?debug=true",
                "status": "503",
            },
            "jsonPayload": {"message": "FooError: boom", "logger": "app"},
        }

        self.assertEqual(
            _extract_http_request_info(entry),
            {"httpStatus": 503, "endpoint": "/foo/bar?debug=true"},
        )

    def test_extract_http_request_info_falls_back_to_json_payload_request(self):
        entry = {
            "timestamp": "2026-04-05T00:00:00.000000Z",
            "severity": "ERROR",
            "jsonPayload": {
                "message": "FooError: boom",
                "logger": "app",
                "request": {
                    "path": "/foo/bar",
                    "status": 502,
                },
            },
        }

        self.assertEqual(
            _extract_http_request_info(entry),
            {"httpStatus": 502, "endpoint": "/foo/bar"},
        )

    def test_extract_http_request_info_returns_status_none_when_missing(self):
        entry = {
            "timestamp": "2026-04-05T00:00:00.000000Z",
            "severity": "ERROR",
            "jsonPayload": {
                "message": "FooError: boom",
                "logger": "app",
                "request": {"path": "/foo/bar"},
            },
        }

        self.assertEqual(
            _extract_http_request_info(entry),
            {"httpStatus": None, "endpoint": "/foo/bar"},
        )

    def test_extract_http_request_info_returns_none_when_no_endpoint(self):
        entry = {
            "timestamp": "2026-04-05T00:00:00.000000Z",
            "severity": "ERROR",
            "jsonPayload": {"message": "FooError: boom", "logger": "app"},
        }

        self.assertIsNone(_extract_http_request_info(entry))

    def test_extract_http_request_info_merges_status_from_later_candidate(self):
        entry = {
            "timestamp": "2026-04-05T00:00:00.000000Z",
            "severity": "ERROR",
            "httpRequest": {"status": "503"},
            "jsonPayload": {
                "message": "FooError: boom",
                "logger": "app",
                "request": {"path": "/foo/bar"},
            },
        }

        self.assertEqual(
            _extract_http_request_info(entry),
            {"httpStatus": 503, "endpoint": "/foo/bar"},
        )

    def test_collect_endpoint_candidates_ranks_and_limits_entries(self):
        logs = [
            make_trace_log(
                "2026-04-05T00:00:00.000000Z",
                "ERROR",
                "FooError: boom",
                request={"path": "/foo", "status": 503},
            ),
            make_trace_log(
                "2026-04-05T00:00:01.000000Z",
                "ERROR",
                "FooError: boom",
                request={"path": "/foo", "status": 500},
            ),
            make_trace_log(
                "2026-04-05T00:00:02.000000Z",
                "ERROR",
                "FooError: boom",
                request={"path": "/bar", "status": 502},
            ),
        ]

        self.assertEqual(
            _collect_endpoint_candidates(logs, limit=1),
            [{"endpoint": "/foo", "count": 2, "httpStatuses": [503, 500]}],
        )

    def test_collect_endpoint_candidates_returns_empty_when_no_endpoint(self):
        logs = [
            make_trace_log("2026-04-05T00:00:00.000000Z", "ERROR", "FooError: boom")
        ]

        self.assertEqual(_collect_endpoint_candidates(logs), [])

    def test_collect_message_variants_handles_empty_and_duplicate_values(self):
        self.assertEqual(_collect_message_variants([]), [])
        self.assertEqual(
            _collect_message_variants(
                [
                    {"message": "FooError: boom"},
                    {"message": "FooError: boom"},
                ]
            ),
            [{"value": "FooError: boom", "count": 2}],
        )

    def test_collect_logger_clues_handles_empty_and_duplicate_values(self):
        self.assertEqual(_collect_logger_clues([]), [])
        self.assertEqual(
            _collect_logger_clues(
                [
                    {"logger": "app"},
                    {"logger": "app"},
                    {"logger": ""},
                ]
            ),
            [{"value": "app", "count": 2}],
        )

    def test_find_first_trace_id_scans_all_matched_logs(self):
        logs = [
            make_trace_log("2026-04-05T00:00:00.000000Z", "ERROR", "FooError: boom"),
            make_trace_log(
                "2026-04-05T00:00:01.000000Z",
                "ERROR",
                "FooError: boom",
                trace_id="trace-123",
            ),
        ]

        self.assertEqual(_find_first_trace_id(logs), "trace-123")

    def test_find_first_trace_id_returns_none_for_empty_logs(self):
        self.assertIsNone(_find_first_trace_id([]))

    def test_find_first_trace_entry_returns_entry_with_trace_id(self):
        logs = [
            make_trace_log("2026-04-05T00:00:00.000000Z", "ERROR", "FooError: boom"),
            make_trace_log(
                "2026-04-05T00:00:01.000000Z",
                "ERROR",
                "FooError: boom",
                trace_id="trace-123",
            ),
        ]

        self.assertEqual(extract_trace_id(_find_first_trace_entry(logs)), "trace-123")

    def test_extract_service_name_prefers_resource_labels(self):
        entry = {
            "resource": {
                "labels": {
                    "service_name": "svc-a",
                    "configuration_name": "cfg-a",
                }
            }
        }

        self.assertEqual(_extract_service_name(entry), "svc-a")


class ProdErrorsAnsiTest(unittest.TestCase):
    def test_display_width_counts_wide_chars(self):
        self.assertEqual(display_width("abc"), 3)
        self.assertEqual(display_width("ログ"), 4)

    def test_padding_uses_display_width(self):
        self.assertEqual(pad_right("ログ", 6), "ログ  ")
        self.assertEqual(pad_left("12", 4), "  12")

    def test_trunc_uses_display_width(self):
        self.assertEqual(trunc("ログイン時にエラー", 8), "ログイ…")


class ProdErrorsTimefmtTest(unittest.TestCase):
    def test_parse_timestamp_returns_none_for_empty_value(self):
        self.assertIsNone(parse_timestamp(""))

    def test_parse_timestamp_converts_offset_to_utc(self):
        parsed = parse_timestamp("2026-04-14T10:23:45+09:00")
        self.assertEqual(parsed.isoformat(), "2026-04-14T01:23:45+00:00")

    def test_parse_timestamp_treats_naive_as_utc(self):
        parsed = parse_timestamp("2026-04-14T01:23:45")
        self.assertEqual(parsed.isoformat(), "2026-04-14T01:23:45+00:00")

    def test_parse_timestamp_returns_none_for_invalid_value(self):
        self.assertIsNone(parse_timestamp("not-a-timestamp"))

    def test_format_jst_timestamp_converts_utc_to_jst(self):
        self.assertEqual(
            format_jst_timestamp("2026-04-14T01:23:45.205000Z", include_seconds=True),
            "2026-04-14 10:23:45 JST",
        )

    def test_format_jst_timestamp_includes_millis_with_seconds(self):
        self.assertEqual(
            format_jst_timestamp("2026-04-14T01:23:45.205000Z", include_millis=True),
            "2026-04-14 10:23:45.205 JST",
        )

    def test_format_relative_age_returns_minutes(self):
        self.assertEqual(
            format_relative_age(
                "2026-04-14T01:00:00.000000Z",
                now=datetime(2026, 4, 14, 1, 18, tzinfo=timezone.utc),
            ),
            "18m ago",
        )

    def test_format_relative_age_returns_just_now(self):
        self.assertEqual(
            format_relative_age(
                "2026-04-14T01:17:45.000000Z",
                now=datetime(2026, 4, 14, 1, 18, tzinfo=timezone.utc),
            ),
            "just now",
        )

    def test_format_relative_age_returns_hours(self):
        self.assertEqual(
            format_relative_age(
                "2026-04-13T23:00:00.000000Z",
                now=datetime(2026, 4, 14, 1, 18, tzinfo=timezone.utc),
            ),
            "2h ago",
        )

    def test_format_relative_age_returns_days(self):
        self.assertEqual(
            format_relative_age(
                "2026-04-12T01:18:00.000000Z",
                now=datetime(2026, 4, 14, 1, 18, tzinfo=timezone.utc),
            ),
            "2d ago",
        )

    def test_format_summary_last_seen_combines_absolute_and_relative(self):
        self.assertEqual(
            format_summary_last_seen(
                "2026-04-14T01:00:00.000000Z",
                now=datetime(2026, 4, 14, 1, 18, tzinfo=timezone.utc),
            ),
            "2026-04-14 10:00 JST (18m ago)",
        )

    def test_format_summary_last_seen_returns_empty_for_empty_value(self):
        self.assertEqual(format_summary_last_seen(""), "")


class ProdErrorsClientTest(unittest.TestCase):
    @mock.patch("prod_errors.client.logging_query")
    def test_logging_list_all_follows_pagination(self, mock_logging_query):
        mock_logging_query.side_effect = [
            {
                "entries": [{"timestamp": "2026-04-01T00:00:00.000000Z"}],
                "nextPageToken": "next",
            },
            {"entries": [{"timestamp": "2026-04-02T00:00:00.000000Z"}]},
        ]

        entries = logging_list_all("demo", "token", "severity>=ERROR", limit=1)

        self.assertEqual(len(entries), 2)
        self.assertEqual(mock_logging_query.call_count, 2)


class ProdErrorsCliTest(unittest.TestCase):
    def test_build_parser_supports_hotspots(self):
        parser = build_parser()

        args = parser.parse_args(
            [
                "--project",
                "demo",
                "hotspots",
                "--period",
                "7d",
                "--until",
                "2026-04-01T00:00:00Z",
                "--bucket",
                "7d",
            ]
        )

        self.assertEqual(args.command, "hotspots")
        self.assertEqual(args.project, "demo")
        self.assertEqual(args.period, "7d")
        self.assertEqual(args.until, "2026-04-01T00:00:00Z")
        self.assertEqual(args.bucket, "7d")

    def test_build_parser_supports_trace_request_mode(self):
        parser = build_parser()

        args = parser.parse_args(
            [
                "--project",
                "demo",
                "trace",
                "g-trace",
                "--mode",
                "requests",
                "--window",
                "10m",
            ]
        )

        self.assertEqual(args.command, "trace")
        self.assertEqual(args.mode, "requests")
        self.assertEqual(args.window, "10m")

    def test_hotspots_since_help_mentions_range_start(self):
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

        self.assertIn("Range start timestamp", since_action.help)


class ProdErrorsCommandHelpersTest(unittest.TestCase):
    @mock.patch("prod_errors.commands.logging_query")
    def test_find_prior_occurrences_batches_groups(self, mock_logging_query):
        mock_logging_query.return_value = {
            "entries": [
                make_hotspot_log(
                    "2026-03-31T23:00:00.000000Z", "g-old", "FooError: old"
                )
            ]
        }

        prior = _find_prior_occurrences(
            "demo",
            "token",
            ["g-old", "g-new"],
            "2026-04-01T00:00:00.000000Z",
            {
                "g-old": {"firstSeenTime": "2026-03-31T23:00:00.000000Z"},
                "g-new": {},
            },
        )

        self.assertEqual(prior["g-old"], True)
        self.assertEqual(prior["g-new"], False)

    @mock.patch("prod_errors.commands.datetime")
    def test_resolve_hotspot_window_defaults_to_period_from_now(self, mock_datetime):
        mock_datetime.now.return_value = datetime(2026, 4, 5, 0, 0, tzinfo=timezone.utc)
        args = argparse.Namespace(since=None, until=None, period="7d")

        since, until = _resolve_hotspot_window(args)

        self.assertEqual(since, "2026-03-29T00:00:00.000000Z")
        self.assertEqual(until, "2026-04-05T00:00:00.000000Z")

    def test_resolve_hotspot_window_uses_explicit_since_and_until(self):
        args = argparse.Namespace(
            since="2026-04-01T00:00:00Z",
            until="2026-04-05T00:00:00Z",
            period="30d",
        )

        since, until = _resolve_hotspot_window(args)

        self.assertEqual(since, "2026-04-01T00:00:00.000000Z")
        self.assertEqual(until, "2026-04-05T00:00:00.000000Z")

    def test_resolve_hotspot_window_rejects_inverted_range(self):
        args = argparse.Namespace(
            since="2026-04-05T00:00:00Z",
            until="2026-04-05T00:00:00Z",
            period="30d",
        )

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                _resolve_hotspot_window(args)

    def test_parser_rejects_bucket_wider_than_window(self):
        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            since="2026-04-05T00:00:00Z",
            until="2026-04-05T12:00:00Z",
            period="30d",
            bucket="1d",
            limit=20,
            json=True,
        )

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                cmd_hotspots(args)


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

    @mock.patch("prod_errors.timefmt.now_utc")
    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch("prod_errors.commands.api_get_all_pages")
    def test_cmd_summary_output_uses_jst_and_relative_last_seen(
        self,
        mock_api_get_all_pages,
        _mock_get_token,
        mock_now_utc,
    ):
        mock_now_utc.return_value = datetime(2026, 4, 5, 0, 18, tzinfo=timezone.utc)
        mock_api_get_all_pages.return_value = [
            make_group(
                "g-open",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-05T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
            )
        ]

        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            group_by=None,
            since=None,
            json=False,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_summary(args)

        output = stdout.getvalue()
        self.assertIn("First", output)
        self.assertIn("Last", output)
        self.assertIn("2026-04-05 09:00 JST", output)
        self.assertIn("2026-04-05 09:00 JST (18m ago)", output)

    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch(
        "prod_errors.commands._find_prior_occurrences",
        return_value={"g-open": False},
    )
    @mock.patch("prod_errors.commands.api_get_all_pages_with_progress")
    @mock.patch("prod_errors.commands.logging_list_all")
    def test_cmd_hotspots_json_filters_status_and_uses_buckets(
        self,
        mock_logging_list_all,
        mock_api_get_all_pages_with_progress,
        _mock_find_prior_occurrences,
        _mock_get_token,
    ):
        mock_logging_list_all.return_value = [
            make_hotspot_log(
                "2026-04-03T00:10:00.000000Z", "g-open", "FooError: boom", "svc-a"
            ),
            make_hotspot_log(
                "2026-04-03T02:10:00.000000Z",
                "g-resolved",
                "BarError: boom",
                "svc-b",
            ),
        ]
        mock_api_get_all_pages_with_progress.return_value = [
            make_group(
                "g-open",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
            ),
            make_group(
                "g-resolved",
                "RESOLVED",
                "BarError: boom",
                8,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-06T00:00:00.000000Z",
                "svc-b",
            ),
        ]

        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            since="2026-04-02T12:00:00Z",
            until="2026-04-04T00:00:00Z",
            period="30d",
            bucket="1d",
            limit=20,
            json=True,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["total"], 1)
        self.assertEqual(payload["shown"], 1)
        self.assertEqual(payload["summary"]["totalGroups"], 1)
        self.assertEqual(payload["summary"]["newGroups"], 1)
        self.assertEqual(payload["buckets"][0]["activeGroups"], 1)
        self.assertEqual(payload["errors"][0]["groupId"], "g-open")
        self.assertEqual(payload["errors"][0]["activeBuckets"], 1)
        self.assertTrue(payload["errors"][0]["isNewInRange"])

    @mock.patch("prod_errors.timefmt.now_utc")
    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch(
        "prod_errors.commands._find_prior_occurrences",
        return_value={"g-open": False},
    )
    @mock.patch("prod_errors.commands.api_get_all_pages_with_progress")
    @mock.patch("prod_errors.commands.logging_list_all")
    def test_cmd_hotspots_output_uses_jst_and_relative_last_seen(
        self,
        mock_logging_list_all,
        mock_api_get_all_pages_with_progress,
        _mock_find_prior_occurrences,
        _mock_get_token,
        mock_now_utc,
    ):
        mock_now_utc.return_value = datetime(2026, 4, 5, 0, 18, tzinfo=timezone.utc)
        mock_api_get_all_pages_with_progress.return_value = [
            make_group(
                "g-open",
                "OPEN",
                "FooError: boom",
                5,
                "2026-04-05T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
            )
        ]
        mock_logging_list_all.return_value = [
            make_hotspot_log(
                "2026-04-05T00:10:00.000000Z", "g-open", "FooError: boom", "svc-a"
            )
        ]

        args = argparse.Namespace(
            project="demo",
            status="OPEN,ACKNOWLEDGED,RESOLVED",
            since="2026-04-05T00:00:00Z",
            until="2026-04-06T00:00:00Z",
            period="30d",
            bucket="1d",
            limit=20,
            json=False,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        output = stdout.getvalue()
        self.assertIn("Error Hotspots", output)
        self.assertIn("Range Summary", output)
        self.assertIn("Bucket Summary", output)
        self.assertIn("First-seen", output)
        self.assertIn("Known", output)
        self.assertIn("First", output)
        self.assertIn("Last", output)
        self.assertIn("2026-04-05 09:10 JST", output)
        self.assertIn("2026-04-05 09:10 JST (8m ago)", output)

    @mock.patch("prod_errors.commands.logging_list_all")
    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch("prod_errors.commands.api_get_all_pages")
    def test_cmd_hotspots_without_until_uses_fast_path(
        self,
        mock_api_get_all_pages,
        _mock_get_token,
        mock_logging_list_all,
    ):
        mock_api_get_all_pages.return_value = [
            make_group(
                "g-fast",
                "OPEN",
                "FastError: boom",
                5,
                "2026-04-01T00:00:00.000000Z",
                "2026-04-05T00:00:00.000000Z",
                "svc-a",
                timed_counts=[
                    {
                        "count": "3",
                        "startTime": "2026-04-04T00:00:00.000000Z",
                        "endTime": "2026-04-05T00:00:00.000000Z",
                    }
                ],
            )
        ]
        mock_logging_list_all.side_effect = AssertionError(
            "fast path should not scan Cloud Logging"
        )

        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            since="2026-04-04T00:00:00Z",
            until=None,
            period="7d",
            bucket="1d",
            limit=20,
            json=True,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["summary"]["totalGroups"], 1)
        self.assertEqual(payload["errors"][0]["groupId"], "g-fast")
        self.assertEqual(payload["errors"][0]["activeBuckets"], 1)
        self.assertEqual(payload["buckets"][0]["activeGroups"], 1)
        self.assertEqual(payload["buckets"][0]["eventCount"], 3)

    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch(
        "prod_errors.commands._find_prior_occurrences",
        return_value={},
    )
    @mock.patch("prod_errors.commands.api_get_all_pages_with_progress", return_value=[])
    @mock.patch("prod_errors.commands.logging_list_all", return_value=[])
    def test_cmd_hotspots_json_keeps_empty_summary_shape(
        self,
        _mock_logging_list_all,
        _mock_api_get_all_pages_with_progress,
        _mock_find_prior_occurrences,
        _mock_get_token,
    ):
        args = argparse.Namespace(
            project="demo",
            status="OPEN,ACKNOWLEDGED,RESOLVED",
            since="2026-04-01T00:00:00Z",
            until="2026-04-02T00:00:00Z",
            period="30d",
            bucket="1d",
            limit=20,
            json=True,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["summary"]["totalGroups"], 0)
        self.assertEqual(payload["summary"]["newGroups"], 0)
        self.assertEqual(payload["summary"]["recurringGroups"], 0)
        self.assertEqual(payload["total"], 0)
        self.assertEqual(len(payload["buckets"]), 1)

    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch(
        "prod_errors.commands._find_prior_occurrences",
        return_value={"g-historical": True},
    )
    @mock.patch(
        "prod_errors.commands.api_get_optional",
        return_value={"groupId": "g-historical", "resolutionStatus": "OPEN"},
    )
    @mock.patch("prod_errors.commands.api_get_all_pages_with_progress", return_value=[])
    @mock.patch("prod_errors.commands.logging_list_all")
    def test_cmd_hotspots_uses_group_get_fallback_for_historical_metadata(
        self,
        mock_logging_list_all,
        _mock_api_get_all_pages_with_progress,
        _mock_api_get_optional,
        _mock_find_prior_occurrences,
        _mock_get_token,
    ):
        mock_logging_list_all.return_value = [
            make_hotspot_log(
                "2026-01-15T00:10:00.000000Z",
                "g-historical",
                "OldError: boom",
                "svc-legacy",
            )
        ]
        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            since="2026-01-01T00:00:00Z",
            until="2026-02-01T00:00:00Z",
            period="30d",
            bucket="7d",
            limit=20,
            json=True,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["summary"]["totalGroups"], 1)
        self.assertEqual(payload["errors"][0]["status"], "OPEN")
        self.assertEqual(payload["errors"][0]["groupId"], "g-historical")
        self.assertEqual(payload["errors"][0]["isRecurringInRange"], True)

    @mock.patch("prod_errors.commands.get_token", return_value="token")
    @mock.patch("prod_errors.commands.api_get_optional", return_value=None)
    @mock.patch("prod_errors.commands.api_get_all_pages_with_progress", return_value=[])
    @mock.patch("prod_errors.commands.logging_list_all")
    def test_cmd_hotspots_reports_skipped_groups_when_metadata_missing(
        self,
        mock_logging_list_all,
        _mock_api_get_all_pages_with_progress,
        _mock_api_get_optional,
        _mock_get_token,
    ):
        mock_logging_list_all.return_value = [
            make_hotspot_log(
                "2026-01-15T00:10:00.000000Z",
                "g-missing",
                "OldError: boom",
                "svc-legacy",
            )
        ]
        args = argparse.Namespace(
            project="demo",
            status="OPEN",
            since="2026-01-01T00:00:00Z",
            until="2026-02-01T00:00:00Z",
            period="30d",
            bucket="7d",
            limit=20,
            json=True,
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_hotspots(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["summary"]["totalGroups"], 0)
        self.assertEqual(payload["skippedGroups"]["count"], 1)
        self.assertEqual(payload["skippedGroups"]["groupIds"], ["g-missing"])

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
            mode="trace",
            window="5m",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(args)

        output = stdout.getvalue()
        self.assertIn("## Error Group: g-trace", output)
        self.assertIn("### Diagnostic Summary", output)
        self.assertIn("- Service: svc-a", output)
        self.assertIn("Endpoint Candidates", output)
        self.assertIn("  - (not found)", output)
        self.assertIn("### Matched Error Logs", output)
        self.assertIn("[2026-04-05 09:00:00.000 JST]", output)
        self.assertIn("Cloud Trace ID: (not found)", output)
        self.assertIn(
            "Cloud Trace ID was not found; Request Lifecycle is unavailable.", output
        )
        self.assertNotIn("- Count:", output)
        self.assertNotIn("- First:", output)
        self.assertNotIn("- Last:", output)
        self.assertNotIn("### Request Lifecycle", output)
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
            mode="trace",
            window="5m",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(args)

        output = stdout.getvalue()
        self.assertIn("No matching logs in Cloud Logging", output)
        self.assertIn("### Recent Events (1)", output)
        self.assertIn("2026-04-05 09:00:00 JST", output)
        self.assertNotIn("### Matched Error Logs", output)

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    def test_cmd_trace_extracts_endpoint_from_matched_log_without_cloud_trace_id(
        self,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.return_value = [
            {
                "timestamp": "2026-04-05T00:00:00.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "FooError: boom",
                    "logger": "app",
                    "request": {
                        "path": "/foo/bar?debug=true",
                        "status": 503,
                    },
                },
            }
        ]

        args = argparse.Namespace(
            project="demo",
            group_id="g-trace",
            json=False,
            freshness="30d",
            mode="trace",
            window="5m",
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(args)

        output = stdout.getvalue()
        self.assertIn("- Cloud Trace ID: (not found)", output)
        self.assertIn("### Diagnostic Summary", output)
        self.assertIn("Endpoint Candidates", output)
        self.assertIn("`/foo/bar?debug=true` | 1 | HTTP 503", output)
        self.assertIn("### Matched Error Logs", output)
        self.assertIn(
            "Cloud Trace ID was not found; Request Lifecycle is unavailable.", output
        )
        self.assertNotIn("### Request Lifecycle", output)

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    @mock.patch("prod_errors.correlation.logging_read")
    @mock.patch("prod_errors.correlation.logging_list_all")
    def test_cmd_trace_auto_json_correlates_nearby_requests_without_trace_id(
        self,
        mock_correlation_logging_list_all,
        mock_correlation_logging_read,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        request_id = "20337152-1406-4727-9e11-a67722f22be6"
        file_ids = ["aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"]
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.return_value = [
            {
                "timestamp": "2026-04-05T00:57:58.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "FooError: boom",
                    "logger": "app",
                    "request": {"path": "/foo", "status": 500},
                },
            }
        ]
        mock_correlation_logging_list_all.return_value = [
            make_access_log(
                "2026-04-05T00:50:00.000000Z",
                200,
                trace_id="trace-other",
            ),
            make_request_info_log(
                "2026-04-05T00:50:00.100000Z",
                "dd790000-0000-4000-8000-000000000000",
                ["bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"],
                trace_id="trace-other",
            ),
            make_access_log(
                "2026-04-05T00:53:57.000000Z",
                200,
                trace_id="trace-ok",
            ),
            make_request_info_log(
                "2026-04-05T00:53:57.100000Z",
                request_id,
                file_ids,
                trace_id="trace-ok",
            ),
            make_access_log(
                "2026-04-05T00:57:58.000000Z",
                500,
                trace_id="trace-fail-1",
            ),
            make_request_info_log(
                "2026-04-05T00:57:58.100000Z",
                request_id,
                file_ids,
                trace_id="trace-fail-1",
            ),
            make_access_log(
                "2026-04-05T00:58:00.000000Z",
                500,
                trace_id="trace-fail-2",
            ),
            make_request_info_log(
                "2026-04-05T00:58:00.100000Z",
                request_id,
                file_ids,
                trace_id="trace-fail-2",
            ),
        ]
        mock_correlation_logging_read.return_value = [
            make_trace_log(
                "2026-04-05T00:57:59.000000Z",
                "ERROR",
                'duplicate key value violates unique constraint "foo_pkey"',
            )
        ]

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(
                argparse.Namespace(
                    project="demo",
                    group_id="g-trace",
                    json=True,
                    freshness="30d",
                    mode="auto",
                    window="5m",
                )
            )

        payload = json.loads(stdout.getvalue())
        correlation = payload["requestCorrelation"]
        self.assertEqual(correlation["summary"]["successCount"], 1)
        self.assertEqual(correlation["summary"]["failureCount"], 2)
        self.assertEqual(
            correlation["replayCheck"]["signals"],
            [
                "same_request_id",
                "same_file_ids",
                "same_endpoint",
                "success_then_failure",
            ],
        )
        self.assertEqual(correlation["replayCheck"]["verdict"], "likely_resubmit")
        self.assertEqual(len(correlation["relatedConstraintErrors"]), 1)
        self.assertEqual(correlation["correlatedRequests"][0]["requestId"], request_id)
        self.assertEqual(correlation["correlatedRequests"][0]["status"], 200)
        self.assertEqual(correlation["correlatedRequests"][1]["status"], 500)
        self.assertEqual(correlation["correlatedRequests"][2]["status"], 500)
        self.assertEqual(correlation["candidateRequestCount"], 4)
        self.assertEqual(len(correlation["correlatedRequests"]), 3)
        self.assertEqual(
            mock_correlation_logging_list_all.call_args.kwargs["order_by"],
            "timestamp asc",
        )
        self.assertEqual(
            mock_correlation_logging_list_all.call_args.kwargs["max_entries"], 5000
        )

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    @mock.patch("prod_errors.correlation.logging_read")
    @mock.patch("prod_errors.correlation.logging_list_all")
    def test_cmd_trace_requests_mode_prints_request_comparison(
        self,
        mock_correlation_logging_list_all,
        mock_correlation_logging_read,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.return_value = [
            {
                "timestamp": "2026-04-05T00:57:58.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "FooError: boom",
                    "logger": "app",
                    "request": {"path": "/foo", "status": 500},
                },
            }
        ]
        mock_correlation_logging_list_all.return_value = [
            make_access_log(
                "2026-04-05T00:50:00.000000Z",
                200,
                trace_id="trace-other",
            ),
            make_request_info_log(
                "2026-04-05T00:50:00.100000Z",
                "dd790000-0000-4000-8000-000000000000",
                ["bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"],
                trace_id="trace-other",
            ),
            make_access_log(
                "2026-04-05T00:53:57.000000Z",
                200,
                trace_id="trace-ok",
            ),
            make_request_info_log(
                "2026-04-05T00:53:57.100000Z",
                "req-1",
                ["aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"],
                trace_id="trace-ok",
            ),
            make_access_log(
                "2026-04-05T00:57:58.000000Z",
                500,
                trace_id="trace-fail-1",
            ),
            make_request_info_log(
                "2026-04-05T00:57:58.100000Z",
                "req-1",
                ["aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"],
                trace_id="trace-fail-1",
            ),
            make_access_log(
                "2026-04-05T00:58:00.000000Z",
                500,
                trace_id="trace-fail-2",
            ),
            make_request_info_log(
                "2026-04-05T00:58:00.100000Z",
                "req-1",
                ["aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"],
                trace_id="trace-fail-2",
            ),
        ]
        mock_correlation_logging_read.return_value = []

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(
                argparse.Namespace(
                    project="demo",
                    group_id="g-trace",
                    json=False,
                    freshness="30d",
                    mode="requests",
                    window="5m",
                )
            )

        output = stdout.getvalue()
        self.assertIn("### Request Comparison", output)
        self.assertIn("likely_resubmit", output)
        self.assertNotIn("endpoint_failures_seen", output)
        self.assertIn("1 success / 2 failure", output)
        self.assertIn("| Time | Status | Trace | Request | Fingerprint |", output)

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    @mock.patch("prod_errors.correlation.logging_read")
    @mock.patch("prod_errors.correlation.logging_list_all")
    def test_cmd_trace_requests_mode_marks_fingerprint_unavailable(
        self,
        mock_correlation_logging_list_all,
        mock_correlation_logging_read,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.return_value = [
            {
                "timestamp": "2026-04-05T00:57:58.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "FooError: boom",
                    "logger": "app",
                    "request": {"path": "/foo", "status": 500},
                },
            }
        ]
        mock_correlation_logging_list_all.return_value = [
            make_access_log("2026-04-05T00:53:57.000000Z", 200),
            make_access_log("2026-04-05T00:57:58.000000Z", 500),
        ]
        mock_correlation_logging_read.return_value = []

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(
                argparse.Namespace(
                    project="demo",
                    group_id="g-trace",
                    json=True,
                    freshness="30d",
                    mode="requests",
                    window="5m",
                )
            )

        payload = json.loads(stdout.getvalue())
        correlation = payload["requestCorrelation"]
        self.assertEqual(
            correlation["replayCheck"]["verdict"], "fingerprint_unavailable"
        )
        self.assertIn(
            "request fingerprint extraction failed", correlation["summary"]["text"]
        )

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    def test_cmd_trace_prints_endpoint_from_lifecycle_when_matched_log_lacks_endpoint(
        self,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.side_effect = [
            [
                {
                    "timestamp": "2026-04-05T00:57:58.000000Z",
                    "severity": "ERROR",
                    "resource": {"labels": {"service_name": "svc-a"}},
                    "jsonPayload": {
                        "message": "FooError: boom",
                        "logger": "app",
                        "trace_id": "trace-123",
                    },
                }
            ],
            [
                make_trace_log(
                    "2026-04-05T00:57:58.000000Z",
                    "ERROR",
                    "500 request: POST - /api/smart-hanko in 20ms",
                )
            ],
            [],
        ]

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            cmd_trace(
                argparse.Namespace(
                    project="demo",
                    group_id="g-trace",
                    json=False,
                    freshness="30d",
                    mode="trace",
                    window="5m",
                )
            )

        output = stdout.getvalue()
        self.assertIn("- Endpoint: `/api/smart-hanko`", output)
        self.assertNotIn("- Endpoint: (not found)", output)

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    def test_cmd_trace_shows_matched_log_analysis_without_cloud_trace_id(
        self,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.return_value = [
            {
                "timestamp": "2026-04-05T00:00:00.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "FooError: boom",
                    "logger": "app",
                    "request": {"path": "/foo", "status": 503},
                },
            },
            {
                "timestamp": "2026-04-05T00:00:01.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "FooError: boom",
                    "logger": "worker",
                    "request": {"path": "/foo", "status": 500},
                },
            },
            {
                "timestamp": "2026-04-05T00:00:02.000000Z",
                "severity": "ERROR",
                "resource": {"labels": {"service_name": "svc-a"}},
                "jsonPayload": {
                    "message": "BarError: timeout",
                    "logger": "app",
                    "request": {"path": "/bar", "status": 500},
                },
            },
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
        self.assertIn("### Diagnostic Summary", output)
        self.assertIn("- Service: svc-a", output)
        self.assertIn("Endpoint Candidates", output)
        self.assertIn("`/foo` | 2 | HTTP 503, HTTP 500", output)
        self.assertIn("`/bar` | 1 | HTTP 500", output)
        self.assertIn("Message Variants", output)
        self.assertIn("FooError: boom | 2", output)
        self.assertIn("BarError: timeout | 1", output)
        self.assertIn("Logger Clues", output)
        self.assertIn("app | 2", output)
        self.assertIn("worker | 1", output)
        self.assertIn("### Matched Error Logs", output)
        self.assertNotIn("### Request Lifecycle", output)

    def test_cmd_trace_json_uses_first_trace_id_found_in_matched_logs(self):
        payload = self._run_trace_json(
            [
                [
                    {
                        "timestamp": "2026-04-05T00:00:02.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                        },
                    },
                    {
                        "timestamp": "2026-04-05T00:00:01.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                            "trace_id": "trace-123",
                        },
                    },
                ],
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
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                        request={"headers": {"x-tenant-id": "tenant-a"}},
                    )
                ],
            ]
        )

        self.assertEqual(payload["cloudLogging"]["traceId"], "trace-123")
        self.assertIn("lifecycle", payload)
        self.assertIn("retryCheck", payload)

    def test_cmd_trace_json_uses_service_from_trace_id_entry(self):
        payload = self._run_trace_json(
            [
                [
                    {
                        "timestamp": "2026-04-05T00:00:02.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                        },
                    },
                    {
                        "timestamp": "2026-04-05T00:00:01.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-b"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                            "trace_id": "trace-123",
                        },
                    },
                ],
                [],
                [],
            ]
        )

        self.assertEqual(payload["cloudLogging"]["service"], "svc-b")
        self.assertEqual(payload["cloudLogging"]["traceId"], "trace-123")

    def test_cmd_trace_json_includes_matched_log_analysis_without_trace_id(self):
        payload = self._run_trace_json(
            [
                [
                    {
                        "timestamp": "2026-04-05T00:00:00.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                            "request": {"path": "/foo", "status": 503},
                        },
                    },
                    {
                        "timestamp": "2026-04-05T00:00:01.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "worker",
                            "request": {"path": "/foo", "status": 500},
                        },
                    },
                    {
                        "timestamp": "2026-04-05T00:00:02.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "BarError: timeout",
                            "logger": "app",
                            "request": {"path": "/bar", "status": 500},
                        },
                    },
                ]
            ]
        )

        self.assertEqual(payload["cloudLogging"]["traceId"], None)
        self.assertNotIn("lifecycle", payload)
        self.assertEqual(
            payload["cloudLogging"]["endpointCandidates"],
            [
                {"endpoint": "/foo", "count": 2, "httpStatuses": [503, 500]},
                {"endpoint": "/bar", "count": 1, "httpStatuses": [500]},
            ],
        )
        self.assertEqual(
            payload["cloudLogging"]["messageVariants"],
            [
                {"value": "FooError: boom", "count": 2},
                {"value": "BarError: timeout", "count": 1},
            ],
        )
        self.assertEqual(
            payload["cloudLogging"]["loggerClues"],
            [
                {"value": "app", "count": 2},
                {"value": "worker", "count": 1},
            ],
        )

    @mock.patch("prod_errors.trace.get_token", return_value="token")
    @mock.patch("prod_errors.trace.api_get")
    @mock.patch("prod_errors.trace.api_get_all_pages")
    @mock.patch("prod_errors.trace.logging_read")
    def test_cmd_trace_shows_endpoint_before_retry_check_when_trace_id_exists(
        self,
        mock_logging_read,
        mock_api_get_all_pages,
        mock_api_get,
        _mock_get_token,
    ):
        mock_api_get_all_pages.return_value = self._DEFAULT_GROUPS
        mock_api_get.return_value = self._DEFAULT_EVENTS
        mock_logging_read.side_effect = [
            [
                {
                    "timestamp": "2026-04-05T00:00:00.000000Z",
                    "severity": "ERROR",
                    "resource": {"labels": {"service_name": "svc-a"}},
                    "jsonPayload": {
                        "message": "FooError: boom",
                        "logger": "app",
                        "trace_id": "trace-123",
                        "request": {"path": "/foo", "status": 500},
                    },
                }
            ],
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
                    "INFO",
                    "200 OK: GET - /foo in 20ms",
                    logger="access",
                    request={"headers": {"x-tenant-id": "tenant-a"}},
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
        self.assertIn("- Cloud Trace ID: `trace-123`", output)
        self.assertIn("- Endpoint: `/foo` (HTTP 500)", output)
        self.assertIn("### Retry Check", output)
        self.assertGreaterEqual(output.count("- Endpoint: `/foo`"), 2)
        self.assertNotIn("### Diagnostic Summary", output)
        self.assertNotIn("Logger Clues", output)
        self.assertNotIn("Message Variants", output)

    def test_cmd_trace_json_ignores_retry_logs_without_http_status(self):
        payload = self._run_trace_json(
            [
                [
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
                ],
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
                        "INFO",
                        "request completed",
                        logger="app",
                        request={"path": "/foo"},
                    )
                ],
            ]
        )

        self.assertEqual(payload["retryCheck"]["successCount"], 0)
        self.assertEqual(payload["retryCheck"]["failureCount"], 0)
        self.assertEqual(payload["retryCheck"]["verdict"], "no_subsequent_requests")

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

    def test_cmd_trace_json_marks_same_caller_recovery_from_x_app_headers(self):
        payload = self._run_trace_json(
            [
                [
                    {
                        "timestamp": "2026-04-05T00:00:00.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                            "trace_id": "trace-123",
                            "headers": {
                                "X-App-Tenant-Id": "tenant-a",
                                "X-App-Account-Id": "account-a",
                                "X-App-User-Id": "user-a",
                            },
                        },
                    }
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                        request={
                            "headers": {
                                "x-app-tenant-id": "tenant-a",
                                "x-app-account-id": "account-a",
                                "x-app-user-id": "user-a",
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
                                "x-app-tenant-id": "tenant-a",
                                "x-app-account-id": "account-a",
                                "x-app-user-id": "user-a",
                            }
                        },
                    )
                ],
            ]
        )

        self.assertEqual(payload["retryCheck"]["sourceContext"]["tenantId"], "tenant-a")
        self.assertEqual(
            payload["retryCheck"]["sourceContext"]["userAccountId"], "account-a"
        )
        self.assertEqual(payload["retryCheck"]["sourceContext"]["userId"], "user-a")
        self.assertEqual(payload["retryCheck"]["sameTenantSuccessCount"], 1)
        self.assertEqual(payload["retryCheck"]["sameCallerSuccessCount"], 1)
        self.assertEqual(payload["retryCheck"]["verdict"], "recovered_same_caller")

    def test_cmd_trace_json_uses_trace_context_for_retry_access_logs(self):
        payload = self._run_trace_json(
            [
                [
                    {
                        "timestamp": "2026-04-05T00:00:00.000000Z",
                        "severity": "ERROR",
                        "resource": {"labels": {"service_name": "svc-a"}},
                        "jsonPayload": {
                            "message": "FooError: boom",
                            "logger": "app",
                            "trace_id": "trace-123",
                            "context": {
                                "tenantId": "tenant-a",
                                "userAccountId": "ua-1",
                                "userId": "user-1",
                            },
                        },
                    }
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:01.000000Z",
                        "ERROR",
                        "500 Internal Server Error: GET - /foo in 10ms",
                        logger="Application",
                        trace_id="trace-fail",
                    ),
                    make_trace_log(
                        "2026-04-05T00:00:01.001000Z",
                        "INFO",
                        "Response Information GET /foo",
                        logger="Application",
                        trace_id="trace-fail",
                        context={
                            "tenantId": "tenant-a",
                            "userAccountId": "ua-1",
                            "userId": "user-1",
                        },
                    ),
                ],
                [
                    make_trace_log(
                        "2026-04-05T00:00:03.000000Z",
                        "INFO",
                        "200 OK: GET - /foo in 20ms",
                        logger="access",
                        trace_id="trace-ok",
                    ),
                    make_trace_log(
                        "2026-04-05T00:00:03.001000Z",
                        "INFO",
                        "Response Information GET /foo",
                        logger="Application",
                        trace_id="trace-ok",
                        context={
                            "tenantId": "tenant-a",
                            "userAccountId": "ua-1",
                            "userId": "user-1",
                        },
                    ),
                ],
            ]
        )

        self.assertEqual(payload["retryCheck"]["sameTenantSuccessCount"], 1)
        self.assertEqual(payload["retryCheck"]["sameCallerSuccessCount"], 1)
        self.assertEqual(payload["retryCheck"]["verdict"], "recovered_same_caller")

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
        self.assertIn("- Error at: 2026-04-05 09:00:01.000 JST", output)
        self.assertIn("- First success: 2026-04-05 09:00:03.000 JST", output)
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
                        mode="trace",
                        window="5m",
                    )
                )
            return json.loads(stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
