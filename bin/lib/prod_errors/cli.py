import argparse
import os
from prod_errors.commands import cmd_hotspots, cmd_summary, cmd_trace


def build_parser():
    project_from_env = os.environ.get("GCP_PROJECT", "")
    parser = argparse.ArgumentParser(
        prog="prod-errors",
        description="Production Error Reporting investigation tool.",
        epilog=(
            "Examples:\n"
            "  prod-errors summary\n"
            "  prod-errors summary --status OPEN,ACKNOWLEDGED\n"
            "  prod-errors summary --group-by service\n"
            "  prod-errors summary --since 2026-03-10T12:00:00Z\n"
            "  prod-errors hotspots\n"
            "  prod-errors hotspots --since 2026-03-10 --limit 10\n"
            "  prod-errors trace CNrJvq3nnZqKLA\n"
            "  prod-errors --project my-gcp-project summary\n"
            "\n"
            "Configuration:\n"
            "  Set GCP_PROJECT in ~/.zshrc.local (or use --project flag).\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--project",
        default=project_from_env,
        help="GCP project ID (env: GCP_PROJECT)"
        + (f" [{project_from_env}]" if project_from_env else " [REQUIRED]"),
    )

    sub = parser.add_subparsers(dest="command")
    sub.required = True

    summary = sub.add_parser("summary", help="List error groups")
    summary.add_argument(
        "--json",
        action="store_true",
        default=False,
        help="Output as JSON instead of Markdown",
    )
    summary.add_argument(
        "--status", default="OPEN", help="Comma-separated status filter (default: OPEN)"
    )
    summary.add_argument(
        "--group-by", choices=["service"], default=None, help="Group results by service"
    )
    summary.add_argument(
        "--since",
        default=None,
        help="Show errors since timestamp (ISO 8601, e.g. 2026-03-10T12:00:00Z). Useful for post-release monitoring.",
    )

    trace = sub.add_parser("trace", help="Deep-dive into an error group")
    trace.add_argument("group_id", help="Error group ID from summary output")
    trace.add_argument(
        "--json",
        action="store_true",
        default=False,
        help="Output as JSON instead of Markdown",
    )
    trace.add_argument(
        "--freshness",
        default="30d",
        help="Cloud Logging search window (default: 30d). Format: Nd where N is number of days (e.g. 7d, 30d, 90d)",
    )

    hotspots = sub.add_parser(
        "hotspots", help="Rank frequent error groups for weekly improvement discovery"
    )
    hotspots.add_argument(
        "--json",
        action="store_true",
        default=False,
        help="Output as JSON instead of Markdown",
    )
    hotspots.add_argument(
        "--status",
        default="OPEN,ACKNOWLEDGED,RESOLVED",
        help="Comma-separated status filter (default: OPEN,ACKNOWLEDGED,RESOLVED)",
    )
    hotspots.add_argument(
        "--since",
        default=None,
        help="Approximate lower bound inside the selected period. Counts are recalculated from timed buckets when set, and overlapping buckets are counted in full.",
    )
    hotspots.add_argument(
        "--period",
        choices=["1h", "6h", "1d", "7d", "30d"],
        default="30d",
        help="Error Reporting time window (default: 30d)",
    )
    hotspots.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Maximum number of hotspot groups to show (default: 20)",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    if not args.project:
        parser.error(
            "--project is required (or set GCP_PROJECT env var in ~/.zshrc.local)"
        )
    {"summary": cmd_summary, "hotspots": cmd_hotspots, "trace": cmd_trace}[
        args.command
    ](args)
