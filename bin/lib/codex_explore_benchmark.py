from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import subprocess
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .codex_explore import (
    DEFAULT_ASTRA_MODEL,
    DEFAULT_SOL_MODEL,
    DEFAULT_SKILL_PATH,
    RunOptions,
    run_router,
    utc_now,
)


@dataclass(frozen=True)
class BenchmarkCondition:
    key: str
    label: str
    model: str
    effort: str
    mode: str


BENCHMARK_CONDITIONS = {
    "A": BenchmarkCondition("A", "Sol固定", DEFAULT_SOL_MODEL, "medium", "off"),
    "B": BenchmarkCondition(
        "B", "Sol→Astra自動切替", DEFAULT_SOL_MODEL, "medium", "auto"
    ),
    "C": BenchmarkCondition("C", "Astra固定", DEFAULT_ASTRA_MODEL, "low", "off"),
}


def benchmark_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compare Sol, auto-switch, and Astra runs."
    )
    parser.add_argument("--task-file", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--skill-path", type=Path, default=DEFAULT_SKILL_PATH)
    parser.add_argument("--sol-effort", default="medium")
    parser.add_argument("--astra-effort", default="low")
    parser.add_argument("--threshold-seconds", type=float, default=60.0)
    parser.add_argument("--switch-grace-seconds", type=float, default=15.0)
    parser.add_argument("--max-run-seconds", type=float, default=1800.0)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--order", default="A,B,C")
    parser.add_argument("--max-total-seconds", type=float, required=True)
    parser.add_argument("--max-total-credits", type=float, required=True)
    parser.add_argument("--allow-live", action="store_true")
    parser.add_argument("--allow-unmetered", action="store_true")
    parser.add_argument("--codex-command", default="codex")
    return parser


def parse_order(value: str) -> list[BenchmarkCondition]:
    keys = [part.strip().upper() for part in value.split(",") if part.strip()]
    if sorted(keys) != ["A", "B", "C"]:
        raise ValueError("--order must contain A,B,C exactly once")
    return [BENCHMARK_CONDITIONS[key] for key in keys]


def append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def median_or_none(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def token_total(record: dict[str, Any]) -> float | None:
    run_total = record.get("result", {}).get("token_usage", {}).get("run_total")
    if not isinstance(run_total, dict):
        return None
    total_tokens = run_total.get("totalTokens")
    return float(total_tokens) if isinstance(total_tokens, (int, float)) else None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_version(command: str) -> str:
    try:
        completed = subprocess.run(
            [command, "--version"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"unknown ({error})"
    output = (completed.stdout or completed.stderr).strip()
    return output or f"unknown (exit {completed.returncode})"


def git_head(cwd: Path) -> str:
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    value = completed.stdout.strip()
    return value if completed.returncode == 0 and value else "unknown"


def benchmark_manifest(
    output_dir: Path,
    task_file: Path,
    skill_path: Path,
    cwd: Path,
    namespace: argparse.Namespace,
) -> dict[str, Any]:
    manifest = {
        "created_at": utc_now(),
        "task_file": str(task_file),
        "task_sha256": sha256_file(task_file),
        "target_cwd": str(cwd),
        "target_git_head": git_head(cwd),
        "skill_path": str(skill_path),
        "skill_sha256": sha256_file(skill_path),
        "codex_command": namespace.codex_command,
        "codex_version": command_version(namespace.codex_command),
        "models": {
            "sol": DEFAULT_SOL_MODEL,
            "astra": DEFAULT_ASTRA_MODEL,
            "sol_effort": namespace.sol_effort,
            "astra_effort": namespace.astra_effort,
        },
        "threshold_seconds": namespace.threshold_seconds,
        "switch_grace_seconds": namespace.switch_grace_seconds,
        "max_run_seconds": namespace.max_run_seconds,
        "repetitions": namespace.repetitions,
        "order": namespace.order,
        "experiment_budgets": {
            "max_total_seconds": namespace.max_total_seconds,
            "max_total_credits": namespace.max_total_credits,
        },
        "fast_mode": "disabled",
        "memories": "disabled",
        "thread_config": {
            "features": {"fast_mode": False, "memories": False},
            "memories": {"use_memories": False},
            "service_tier": "default",
        },
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def render_benchmark_report(
    path: Path,
    records: list[dict[str, Any]],
    task_file: Path,
    max_total_seconds: float,
    max_total_credits: float,
) -> None:
    lines = [
        "# Codex Explore model benchmark",
        "",
        f"- 課題: `{task_file}`",
        "- 実行単位: 独立した新規app-server/thread",
        f"- 実験上限: {max_total_seconds:g}秒 / {max_total_credits:g} credits",
        "- creditsはApp Serverが返す推定値で、欠損は0としていない。",
        "",
        "## 結果",
        "",
        "| 条件 | 実行数 | 成功数 | 完了時間中央値(秒) | tokens中央値 | credits中央値 | 切替実行確認 | 計測完全性 |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    summaries: dict[str, tuple[float | None, float | None, float | None]] = {}
    for key, condition in BENCHMARK_CONDITIONS.items():
        selected = [record for record in records if record.get("condition") == key]
        successful = [
            record
            for record in selected
            if record.get("result", {}).get("status") == "completed"
        ]
        measured = [
            record
            for record in successful
            if record.get("result", {}).get("measurement_completeness") == "complete"
        ]
        durations = [
            float(record["result"]["duration_seconds"])
            for record in measured
            if isinstance(
                record.get("result", {}).get("duration_seconds"), (int, float)
            )
        ]
        credits = [
            float(record["result"]["estimated_usage_credits"])
            for record in measured
            if isinstance(
                record.get("result", {}).get("estimated_usage_credits"), (int, float)
            )
        ]
        tokens = [
            value for record in measured if (value := token_total(record)) is not None
        ]
        confirmed = sum(
            record.get("result", {}).get("models", {}).get("astra_execution_confirmed")
            is True
            for record in selected
        )
        completeness = sorted(
            {
                record.get("result", {}).get("measurement_completeness", "unknown")
                for record in selected
            }
        )
        summaries[key] = (
            median_or_none(durations),
            median_or_none(credits),
            median_or_none(tokens),
        )
        lines.append(
            f"| {key}: {condition.label} | {len(selected)} | {len(successful)} | "
            f"{format_metric(median_or_none(durations))} | "
            f"{format_metric(median_or_none(tokens))} | "
            f"{format_metric(median_or_none(credits))} | {confirmed}/{len(selected)} | "
            f"{', '.join(completeness) or 'unknown'} |"
        )
    base_duration, base_credits, _ = summaries["A"]
    lines.extend(
        [
            "",
            "## A基準の削減率",
            "",
            "時間短縮率 = (Aの完了時間 - 比較条件の完了時間) / Aの完了時間。",
            "credits削減率 = (Aのcredits - 比較条件のcredits) / Aのcredits。",
            "",
            "| 条件 | 時間短縮率 | credits削減率 |",
            "| --- | ---: | ---: |",
        ]
    )
    for key in ("B", "C"):
        duration, credits, _ = summaries[key]
        time_reduction = (
            (base_duration - duration) / base_duration
            if base_duration and duration is not None
            else None
        )
        credit_reduction = (
            (base_credits - credits) / base_credits
            if base_credits and credits is not None
            else None
        )
        lines.append(
            f"| {key} | {format_percent(time_reduction)} | {format_percent(credit_reduction)} |"
        )
    lines.extend(
        [
            "",
            "## 各run",
            "",
            "| run | 条件 | 状態 | 秒 | credits | 実効モデル | 切替状態 |",
            "| --- | --- | --- | ---: | ---: | --- | --- |",
        ]
    )
    for record in records:
        result = record.get("result", {})
        lines.append(
            f"| `{result.get('run_id', '-')}` | {record.get('condition', '-')} | {result.get('status', '-')} | "
            f"{format_metric(result.get('duration_seconds'))} | {format_metric(result.get('estimated_usage_credits'))} | "
            f"{result.get('models', {}).get('effective', '-')} | {result.get('switch', {}).get('state', '-')} |"
        )
    lines.extend(
        [
            "",
            "## 解釈",
            "",
            "この実験の1回実行だけでは常用判断を確定しない。回答品質は別途、課題ごとの評価基準で確認する。",
            "完了時間はrouter開始から最終turn完了までの経過時間で、純粋な推論時間ではない。",
            "成功数と中央値はstatusがcompletedのrunだけを対象にし、interrupted/failed/timeoutは比較から除外する。",
            "tokensは各threadの累積totalを最後のスナップショットから読み、スナップショット同士を加算していない。",
            "イベントログの再生は制御ロジックのテストであり、Astraの実消費や回答比較には使えない。",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def format_metric(value: Any) -> str:
    if not isinstance(value, (int, float)):
        return "unknown"
    return f"{value:.3f}" if isinstance(value, float) else str(value)


def format_percent(value: float | None) -> str:
    return f"{value:.1%}" if value is not None else "unknown"


def benchmark_main(argv: list[str] | None = None) -> int:
    parser = benchmark_parser()
    namespace = parser.parse_args(argv)
    if not namespace.allow_live:
        parser.error("実モデル実行には --allow-live が必要です")
    if namespace.repetitions < 1:
        parser.error("--repetitions must be positive")
    if (
        namespace.max_total_seconds <= 0
        or namespace.max_total_credits <= 0
        or namespace.max_run_seconds <= 0
    ):
        parser.error("experiment budgets and max run time must be positive")
    if namespace.threshold_seconds < 0 or namespace.switch_grace_seconds < 0:
        parser.error("threshold and switch grace must not be negative")
    try:
        conditions = parse_order(namespace.order)
        task_file = namespace.task_file.expanduser().resolve()
        cwd = namespace.cwd.expanduser().resolve()
        skill_path = namespace.skill_path.expanduser().resolve()
        output_dir = namespace.output_dir.expanduser().resolve()
        if output_dir == cwd or cwd in output_dir.parents:
            parser.error("--output-dir must be outside --cwd")
        prompt = task_file.read_text(encoding="utf-8")
        if not skill_path.is_file():
            parser.error(f"explore skill not found: {skill_path}")
        output_dir.mkdir(parents=True, exist_ok=True)
        benchmark_manifest(output_dir, task_file, skill_path, cwd, namespace)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    records: list[dict[str, Any]] = []
    started = time.monotonic()
    total_credits = 0.0
    events_path = output_dir / "events.jsonl"
    results_path = output_dir / "results.jsonl"
    cancelled = False
    for repetition in range(1, namespace.repetitions + 1):
        for condition in conditions:
            remaining_seconds = namespace.max_total_seconds - (
                time.monotonic() - started
            )
            remaining_credits = namespace.max_total_credits - total_credits
            if remaining_seconds <= 0 or remaining_credits <= 0:
                cancelled = True
                break
            run_id = f"{condition.key}-{repetition}-{uuid.uuid4().hex[:8]}"
            options = RunOptions(
                prompt=prompt,
                cwd=cwd,
                mode=condition.mode,
                explore=True,
                skill_path=skill_path,
                sol_effort=namespace.sol_effort,
                astra_effort=namespace.astra_effort,
                threshold_seconds=namespace.threshold_seconds,
                switch_grace_seconds=namespace.switch_grace_seconds,
                max_run_seconds=min(namespace.max_run_seconds, remaining_seconds),
                max_estimated_credits=remaining_credits,
                codex_command=namespace.codex_command,
                log_path=events_path,
                answer_path=output_dir / "answers" / f"{run_id}.txt",
                benchmark_config={
                    "features": {"fast_mode": False, "memories": False},
                    "memories": {"use_memories": False},
                    "service_tier": "default",
                },
                run_id=run_id,
            )
            if condition.key == "C":
                options.sol_model = DEFAULT_ASTRA_MODEL
                options.sol_effort = namespace.astra_effort
            result = run_router(options)
            record = {
                "condition": condition.key,
                "condition_label": condition.label,
                "repetition": repetition,
                "result": result,
            }
            records.append(record)
            append_jsonl(results_path, record)
            credits = result.get("estimated_usage_credits")
            if isinstance(credits, (int, float)):
                total_credits += credits
            elif not namespace.allow_unmetered:
                cancelled = True
                break
            if (
                result.get("user_cancelled")
                or result.get("status") == "budget_exceeded"
            ):
                cancelled = True
                break
        if cancelled:
            break
    render_benchmark_report(
        output_dir / "report.md",
        records,
        task_file,
        namespace.max_total_seconds,
        namespace.max_total_credits,
    )
    print(output_dir / "report.md")
    return 0


__all__ = [
    "BENCHMARK_CONDITIONS",
    "BenchmarkCondition",
    "benchmark_main",
    "parse_order",
    "render_benchmark_report",
]
