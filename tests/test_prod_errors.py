import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "bin" / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

from prod_errors.cli import build_parser
from prod_errors.logic import build_hotspot_data, build_service_summary_data, windowed_counts


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


class ProdErrorsCliTest(unittest.TestCase):
    def test_build_parser_supports_hotspots(self):
        parser = build_parser()

        args = parser.parse_args(["--project", "demo", "hotspots", "--period", "7d"])

        self.assertEqual(args.command, "hotspots")
        self.assertEqual(args.project, "demo")
        self.assertEqual(args.period, "7d")


if __name__ == "__main__":
    unittest.main()
