from __future__ import annotations

import argparse
import json
import os
import selectors
import statistics
import subprocess
import sys
import threading
import time
import tomllib
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROUTER_VERSION = "0.1.0"
DEFAULT_SOL_MODEL = "gpt-5.6-sol"
DEFAULT_ASTRA_MODEL = "gpt-6-astra"
DEFAULT_SKILL_PATH = Path.home() / ".codex" / "skills" / "explore" / "SKILL.md"
DEFAULT_LOG_PATH = (
    Path.home() / ".local" / "state" / "codex-explore-router" / "runs.jsonl"
)
HANDOFF_PROMPT = """このタスクを引き継いでください。
目的はセカンドオピニオンの追加ではなく、残りの作業の完了です。

同じthreadのユーザー要件・資料・調査結果・子エージェントの報告を使い、
既に確認済みの事項を広く再調査しないでください。

結論に影響する矛盾や不足情報のみ確認し、
元の依頼に必要な回答と根拠を提示してください。"""
IMPORTANT_ITEM_TYPES = frozenset(
    {
        "commandExecution",
        "collabAgentToolCall",
        "dynamicToolCall",
        "fileChange",
        "mcpToolCall",
        "subAgentActivity",
    }
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def error_text(error: Any) -> str:
    if isinstance(error, dict):
        message = error.get("message")
        if isinstance(message, str) and message:
            return message
    return str(error)


class JsonlLogger:
    def __init__(self, path: Path, run_id: str):
        self.path = path
        self.run_id = run_id
        self.handle = None

    def __enter__(self) -> "JsonlLogger":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open("a", encoding="utf-8")
        return self

    def write(self, event: str, **fields: Any) -> None:
        if self.handle is None:
            raise RuntimeError("logger is not open")
        record = {
            "timestamp": utc_now(),
            "run_id": self.run_id,
            "event": event,
            **fields,
        }
        self.handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True))
        self.handle.write("\n")
        self.handle.flush()

    def __exit__(self, *_: Any) -> None:
        if self.handle is not None:
            self.handle.close()


class AppServerClient:
    def __init__(self, codex_command: str, cwd: Path):
        self.codex_command = codex_command
        self.cwd = cwd
        self.process: subprocess.Popen[str] | None = None
        self.selector = selectors.DefaultSelector()
        self.next_id = 1
        self.stderr_lines: list[str] = []
        self.stderr_thread: threading.Thread | None = None

    def start(self) -> None:
        self.process = subprocess.Popen(
            [self.codex_command, "app-server", "--stdio"],
            cwd=self.cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        assert self.process.stdout is not None
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        assert self.process.stderr is not None
        self.stderr_thread = threading.Thread(
            target=self._drain_stderr,
            args=(self.process.stderr,),
            daemon=True,
        )
        self.stderr_thread.start()

    def _drain_stderr(self, stream: Any) -> None:
        for line in stream:
            if isinstance(line, bytes):
                line = line.decode("utf-8", errors="replace")
            line = line.rstrip()
            if line:
                self.stderr_lines.append(line)
                del self.stderr_lines[:-20]

    def send(self, method: str, params: dict[str, Any] | None = None) -> int:
        if self.process is None or self.process.stdin is None:
            raise RuntimeError("app-server is not running")
        request_id = self.next_id
        self.next_id += 1
        message: dict[str, Any] = {"method": method, "id": request_id}
        if params is not None:
            message["params"] = params
        self.process.stdin.write(
            (json.dumps(message, ensure_ascii=False) + "\n").encode("utf-8")
        )
        self.process.stdin.flush()
        return request_id

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        if self.process is None or self.process.stdin is None:
            raise RuntimeError("app-server is not running")
        message: dict[str, Any] = {"method": method}
        if params is not None:
            message["params"] = params
        self.process.stdin.write(
            (json.dumps(message, ensure_ascii=False) + "\n").encode("utf-8")
        )
        self.process.stdin.flush()

    def read(self, timeout: float | None) -> dict[str, Any] | None:
        ready = self.selector.select(timeout)
        if not ready:
            return None
        stream = ready[0][0].fileobj
        line = stream.readline()
        if not line:
            raise EOFError("app-server closed stdout")
        try:
            message = json.loads(line.decode("utf-8"))
        except json.JSONDecodeError as error:
            raise RuntimeError(f"invalid app-server JSON: {error}") from error
        if not isinstance(message, dict):
            raise RuntimeError("app-server message is not an object")
        return message

    def terminate(self) -> None:
        if self.process is None or self.process.poll() is not None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=2)

    def close(self) -> None:
        try:
            self.selector.close()
        finally:
            self.terminate()


@dataclass
class RunOptions:
    prompt: str
    cwd: Path
    mode: str = "observe"
    explore: bool = False
    skill_path: Path = DEFAULT_SKILL_PATH
    sol_model: str = DEFAULT_SOL_MODEL
    sol_effort: str = "medium"
    astra_model: str = DEFAULT_ASTRA_MODEL
    astra_effort: str = "low"
    threshold_seconds: float = 60.0
    switch_grace_seconds: float = 15.0
    max_run_seconds: float = 1800.0
    max_estimated_credits: float | None = None
    codex_command: str = "codex"
    log_path: Path = DEFAULT_LOG_PATH
    answer_path: Path | None = None
    run_id: str = field(default_factory=lambda: uuid.uuid4().hex)


@dataclass
class RunState:
    run_id: str
    mode: str
    switch_state: str = "not_applicable"
    switch_count: int = 0
    condition_met: bool = False
    request_accepted: bool = False
    astra_execution_confirmed: bool | None = None
    effective_model: str | None = None
    effective_model_source: str | None = None
    requested_model: str | None = None
    thread_id: str | None = None
    active_turn_id: str | None = None
    completed_turns: list[dict[str, Any]] = field(default_factory=list)
    usage_snapshots: list[dict[str, Any]] = field(default_factory=list)
    account_usage: dict[str, Any] | None = None
    errors: list[str] = field(default_factory=list)
    important_items: dict[str, str] = field(default_factory=dict)
    item_counts: dict[str, int] = field(default_factory=dict)
    agent_messages: dict[str, str] = field(default_factory=dict)
    agent_message_order: list[str] = field(default_factory=list)
    models_observed: list[str] = field(default_factory=list)
    user_cancelled: bool = False
    timed_out: bool = False
    natural_completion: bool = False
    final_status: str = "not_started"
    started_monotonic: float = 0.0
    completed_monotonic: float | None = None
    turn_started_monotonic: float | None = None
    fallback_steer_sent: bool = False
    fallback_interrupt_sent: bool = False
    fallback_interrupt_attempted: bool = False
    fallback_turn_started: bool = False
    parent_thread_id: str | None = None


class RouterSession:
    def __init__(self, options: RunOptions, logger: JsonlLogger):
        self.options = options
        self.logger = logger
        self.state = RunState(options.run_id, options.mode)
        self.client = AppServerClient(options.codex_command, options.cwd)
        self.pending: dict[int, str] = {}
        self.deadline: float | None = None
        self.interrupt_deadline: float | None = None

    def log(self, event: str, **fields: Any) -> None:
        self.logger.write(
            event,
            mode=self.state.mode,
            switch_state=self.state.switch_state,
            thread_id=self.state.thread_id,
            turn_id=self.state.active_turn_id,
            effective_model=self.state.effective_model,
            measurement_completeness=self.measurement_completeness(),
            **fields,
        )

    def measurement_completeness(self) -> str:
        has_tokens = bool(self.state.usage_snapshots)
        has_credits = self.estimated_credits() is not None
        has_model = bool(self.state.models_observed)
        present = sum((has_tokens, has_credits, has_model))
        if present == 3:
            return "complete"
        if present:
            return "partial"
        return "unknown"

    def estimated_credits(self) -> float | None:
        usage = self.state.account_usage or {}
        thread_usage = usage.get("threadUsage")
        if not isinstance(thread_usage, dict):
            return None
        micros = thread_usage.get("estimatedUsageCreditsMicros")
        if not isinstance(micros, int):
            return None
        return micros / 1_000_000

    def request_sync(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        timeout: float = 30.0,
    ) -> dict[str, Any]:
        request_id = self.client.send(method, params)
        end = time.monotonic() + timeout
        while True:
            remaining = max(0.0, end - time.monotonic())
            if remaining == 0:
                raise TimeoutError(f"timed out waiting for {method}")
            message = self.client.read(remaining)
            if message is None:
                continue
            if message.get("id") == request_id and (
                "result" in message or "error" in message
            ):
                return message
            self.dispatch(message)

    def request_async(self, method: str, params: dict[str, Any]) -> int:
        request_id = self.client.send(method, params)
        self.pending[request_id] = method
        return request_id

    def dispatch(self, message: dict[str, Any]) -> None:
        if "id" in message and ("result" in message or "error" in message):
            request_id = message["id"]
            method = self.pending.pop(request_id, None)
            if method is not None:
                self.handle_response(method, message)
            return
        method = message.get("method")
        params = message.get("params")
        if isinstance(method, str) and isinstance(params, dict):
            self.handle_notification(method, params)

    def handle_response(self, method: str, message: dict[str, Any]) -> None:
        if "error" in message:
            message_text = error_text(message["error"])
            self.state.errors.append(f"{method}: {message_text}")
            self.log("rpc_error", method=method, error=message["error"])
            if method == "turn/settings/update":
                self.start_fallback("settings_update_failed")
            return
        result = message.get("result")
        if method == "turn/settings/update":
            status = result.get("status") if isinstance(result, dict) else None
            self.log("switch_request_result", method=method, status=status)
            if status == "applied":
                self.state.request_accepted = True
                self.state.switch_state = "request_accepted"
            else:
                self.start_fallback("settings_update_unavailable")
        elif method == "turn/steer":
            self.log("fallback_steer_accepted", method=method, result=result)
            self.interrupt_deadline = (
                time.monotonic() + self.options.switch_grace_seconds
            )
        elif method == "turn/interrupt":
            self.log("fallback_interrupt_accepted", method=method, result=result)
            self.state.fallback_interrupt_sent = True
        elif method == "turn/start":
            self.apply_turn_start(result, fallback=True)
        elif method == "account/usage/read":
            self.state.account_usage = result if isinstance(result, dict) else None
            self.observe_account_usage_models(self.state.account_usage)
            self.log("account_usage", usage=result)

    def handle_notification(self, method: str, params: dict[str, Any]) -> None:
        if method == "thread/started":
            thread = params.get("thread")
            if isinstance(thread, dict) and isinstance(thread.get("id"), str):
                self.log(
                    "thread_started_notification", thread_status=thread.get("status")
                )
            return
        if method == "turn/started":
            turn = params.get("turn")
            if isinstance(turn, dict):
                turn_id = turn.get("id")
                if isinstance(turn_id, str):
                    self.state.active_turn_id = turn_id
                    self.state.turn_started_monotonic = time.monotonic()
                    self.log("turn_started_notification", status=turn.get("status"))
            return
        if method == "turn/completed":
            turn = params.get("turn")
            if isinstance(turn, dict):
                self.handle_turn_completed(turn)
            return
        if method == "thread/tokenUsage/updated":
            usage = params.get("tokenUsage")
            if isinstance(usage, dict):
                self.state.usage_snapshots.append(
                    {
                        "thread_id": params.get("threadId"),
                        "turn_id": params.get("turnId"),
                        "token_usage": usage,
                    }
                )
                self.log("token_usage_updated", token_usage=usage)
            return
        if method == "item/agentMessage/delta":
            item_id = params.get("itemId")
            delta = params.get("delta")
            if isinstance(item_id, str) and isinstance(delta, str):
                if item_id not in self.state.agent_messages:
                    self.state.agent_messages[item_id] = ""
                    self.state.agent_message_order.append(item_id)
                self.state.agent_messages[item_id] += delta
            return
        if method == "item/started":
            item = params.get("item")
            self.handle_item(item, started=True)
            return
        if method == "item/completed":
            item = params.get("item")
            self.handle_item(item, started=False)
            return
        if method == "error":
            self.state.errors.append(error_text(params))
            self.log("server_error", error=params)
            return
        if method == "thread/status/changed":
            self.log("thread_status_changed", status=params.get("status"))

    def handle_item(self, item: Any, started: bool) -> None:
        if not isinstance(item, dict):
            return
        item_id = item.get("id")
        item_type = item.get("type")
        if not isinstance(item_id, str) or not isinstance(item_type, str):
            return
        if started:
            self.state.item_counts[item_type] = (
                self.state.item_counts.get(item_type, 0) + 1
            )
            if item_type in IMPORTANT_ITEM_TYPES:
                self.state.important_items[item_id] = item_type
            self.log("item_started", item_type=item_type, item_id=item_id)
        else:
            self.state.important_items.pop(item_id, None)
            self.log(
                "item_completed",
                item_type=item_type,
                item_id=item_id,
                duration_ms=item.get("durationMs"),
            )
            if item_type == "agentMessage" and isinstance(item.get("text"), str):
                if item_id not in self.state.agent_messages:
                    self.state.agent_message_order.append(item_id)
                self.state.agent_messages[item_id] = item["text"]

    def observe_account_usage_models(self, usage: dict[str, Any] | None) -> None:
        thread_usage = usage.get("threadUsage") if isinstance(usage, dict) else None
        groups = thread_usage.get("groups") if isinstance(thread_usage, dict) else None
        if not isinstance(groups, list):
            return
        for group in groups:
            if not isinstance(group, dict):
                continue
            model = group.get("model")
            if not isinstance(model, str) or not model:
                continue
            if model not in self.state.models_observed:
                self.state.models_observed.append(model)
            self.state.effective_model = model
            self.state.effective_model_source = "usage"
            if model == self.options.astra_model:
                self.state.astra_execution_confirmed = True
                if self.state.request_accepted:
                    self.state.switch_state = "execution_confirmed"

    def apply_turn_start(self, result: Any, fallback: bool = False) -> None:
        turn = result.get("turn") if isinstance(result, dict) else None
        if not isinstance(turn, dict) or not isinstance(turn.get("id"), str):
            self.state.errors.append("turn/start returned no turn")
            return
        self.state.active_turn_id = turn["id"]
        self.state.turn_started_monotonic = time.monotonic()
        if fallback:
            self.state.fallback_turn_started = True
            self.state.switch_state = "fallback_turn_started"
            self.state.request_accepted = True
            self.state.requested_model = self.options.astra_model
            self.log("fallback_turn_started", status=turn.get("status"))
        else:
            self.log("turn_started", status=turn.get("status"))

    def handle_turn_completed(self, turn: dict[str, Any]) -> None:
        turn_id = turn.get("id")
        if not isinstance(turn_id, str):
            return
        self.state.completed_turns.append(
            {
                "id": turn_id,
                "status": turn.get("status"),
                "started_at": turn.get("startedAt"),
                "completed_at": turn.get("completedAt"),
                "duration_ms": turn.get("durationMs"),
                "error": turn.get("error"),
            }
        )
        self.state.important_items.clear()
        self.log("turn_completed", status=turn.get("status"), turn=turn)
        self.state.active_turn_id = None
        self.state.turn_started_monotonic = None
        self.deadline = None
        self.interrupt_deadline = None
        status = turn.get("status")
        if (
            status == "interrupted"
            and self.state.fallback_interrupt_attempted
            and not self.state.fallback_turn_started
            and not self.state.user_cancelled
        ):
            self.start_fallback_turn()
            return
        self.state.natural_completion = status == "completed"
        self.state.final_status = str(status or "unknown")
        self.state.completed_monotonic = time.monotonic()

    def start_fallback(self, reason: str) -> None:
        if self.state.user_cancelled or self.state.active_turn_id is None:
            return
        if self.state.fallback_steer_sent:
            return
        self.state.switch_state = "fallback_requested"
        self.state.fallback_steer_sent = True
        self.log("fallback_steer_requested", reason=reason)
        self.request_async(
            "turn/steer",
            {
                "threadId": self.state.thread_id,
                "expectedTurnId": self.state.active_turn_id,
                "input": [{"type": "text", "text": HANDOFF_PROMPT}],
            },
        )
        self.interrupt_deadline = time.monotonic() + self.options.switch_grace_seconds

    def start_fallback_turn(self) -> None:
        if self.state.user_cancelled or self.state.fallback_turn_started:
            return
        self.state.switch_state = "fallback_turn_requested"
        self.log("fallback_turn_requested")
        self.request_async(
            "turn/start",
            {
                "threadId": self.state.thread_id,
                "model": self.options.astra_model,
                "effort": self.options.astra_effort,
                "input": [{"type": "text", "text": HANDOFF_PROMPT}],
            },
        )

    def switch_eligible(self) -> bool:
        return (
            self.options.mode == "auto"
            and self.options.explore
            and self.state.thread_id is not None
            and self.state.active_turn_id is not None
            and self.state.parent_thread_id is None
            and self.state.switch_count == 0
            and not self.state.user_cancelled
            and self.state.effective_model == self.options.sol_model
            and self.state.effective_model_source == "thread/start"
        )

    def condition_observable(self) -> bool:
        return (
            self.options.mode != "off"
            and self.options.explore
            and self.state.thread_id is not None
            and self.state.active_turn_id is not None
            and self.state.parent_thread_id is None
            and self.state.switch_count == 0
            and self.state.effective_model == self.options.sol_model
            and self.state.effective_model_source == "thread/start"
        )

    def observe_threshold(self, now: float) -> None:
        if self.state.turn_started_monotonic is None:
            return
        if not self.condition_observable():
            return
        elapsed = now - self.state.turn_started_monotonic
        if elapsed < self.options.threshold_seconds or self.state.condition_met:
            return
        self.state.condition_met = True
        self.state.switch_state = "condition_met"
        self.log(
            "switch_condition_met",
            estimated_active_seconds=round(elapsed, 3),
            deferred_for_items=bool(self.state.important_items),
        )

    def maybe_switch(self, now: float) -> None:
        self.observe_threshold(now)
        if not self.state.condition_met:
            return
        if not self.switch_eligible() or self.state.request_accepted:
            return
        if self.state.important_items:
            return
        self.state.switch_count += 1
        self.state.switch_state = "request_sent"
        self.state.requested_model = self.options.astra_model
        self.log("switch_request_sent", requested_model=self.options.astra_model)
        self.request_async(
            "turn/settings/update",
            {
                "threadId": self.state.thread_id,
                "turnId": self.state.active_turn_id,
                "model": self.options.astra_model,
                "effort": self.options.astra_effort,
            },
        )
        self.deadline = now + self.options.switch_grace_seconds

    def maybe_interrupt_fallback(self, now: float) -> None:
        if (
            self.interrupt_deadline is None
            or now < self.interrupt_deadline
            or self.state.active_turn_id is None
            or self.state.fallback_interrupt_attempted
            or self.state.user_cancelled
            or self.state.important_items
        ):
            return
        self.state.switch_state = "fallback_interrupt_requested"
        self.state.fallback_interrupt_attempted = True
        self.log("fallback_interrupt_requested")
        self.request_async(
            "turn/interrupt",
            {
                "threadId": self.state.thread_id,
                "turnId": self.state.active_turn_id,
            },
        )

    def maybe_fallback_after_timeout(self, now: float) -> None:
        if (
            self.deadline is not None
            and now >= self.deadline
            and not self.state.request_accepted
            and not self.state.fallback_steer_sent
        ):
            self.start_fallback("settings_update_timeout")

    def next_timeout(self, now: float) -> float:
        deadlines = [now + 0.5, self.started_deadline()]
        for deadline in (self.deadline, self.interrupt_deadline):
            if deadline is not None:
                deadlines.append(deadline)
        return max(0.0, min(deadlines) - now)

    def started_deadline(self) -> float:
        return self.state.started_monotonic + self.options.max_run_seconds

    def monitor(self) -> None:
        while self.state.active_turn_id is not None:
            now = time.monotonic()
            if now >= self.started_deadline():
                self.state.timed_out = True
                self.state.final_status = "timeout"
                self.log("run_timeout")
                if self.state.active_turn_id is not None:
                    self.request_async(
                        "turn/interrupt",
                        {
                            "threadId": self.state.thread_id,
                            "turnId": self.state.active_turn_id,
                        },
                    )
                break
            self.maybe_switch(now)
            self.maybe_fallback_after_timeout(now)
            self.maybe_interrupt_fallback(now)
            try:
                message = self.client.read(self.next_timeout(now))
            except EOFError as error:
                self.state.errors.append(str(error))
                self.state.final_status = "server_closed"
                self.log("server_closed", stderr=self.client.stderr_lines)
                break
            except (OSError, RuntimeError) as error:
                self.state.errors.append(str(error))
                self.state.final_status = "protocol_error"
                self.log("protocol_error", error=str(error))
                break
            if message is not None:
                self.dispatch(message)

    def run(self) -> dict[str, Any]:
        self.state.started_monotonic = time.monotonic()
        self.log("run_started", requested_model=self.options.sol_model)
        try:
            self.client.start()
            initialize = self.request_sync(
                "initialize",
                {
                    "clientInfo": {
                        "name": "codex-explore-router",
                        "version": ROUTER_VERSION,
                    }
                },
            )
            if "error" in initialize:
                raise RuntimeError(error_text(initialize["error"]))
            self.client.notify("initialized", {})
            models_response = self.request_sync(
                "model/list", {"includeHidden": True, "limit": 100}
            )
            if "error" in models_response:
                raise RuntimeError(error_text(models_response["error"]))
            self.validate_models(models_response.get("result"))
            thread_response = self.request_sync(
                "thread/start",
                {
                    "model": self.options.sol_model,
                    "cwd": str(self.options.cwd),
                    "sandbox": "read-only",
                    "approvalPolicy": "never",
                    "ephemeral": True,
                },
            )
            if "error" in thread_response:
                raise RuntimeError(error_text(thread_response["error"]))
            thread_result = thread_response.get("result")
            thread = (
                thread_result.get("thread") if isinstance(thread_result, dict) else None
            )
            if not isinstance(thread, dict) or not isinstance(thread.get("id"), str):
                raise RuntimeError("thread/start returned no thread")
            self.state.thread_id = thread["id"]
            self.state.effective_model = thread_result.get("model")
            self.state.effective_model_source = "thread/start"
            parent_id = thread.get("parentThreadId")
            self.state.parent_thread_id = parent_id
            if isinstance(self.state.effective_model, str):
                self.state.models_observed.append(self.state.effective_model)
            if parent_id is not None:
                self.state.switch_state = "not_applicable"
            self.log(
                "thread_started",
                cli_version=thread.get("cliVersion"),
                parent_thread_id=parent_id,
                configured_model=thread_result.get("model"),
            )
            turn_response = self.request_sync(
                "turn/start",
                {
                    "threadId": self.state.thread_id,
                    "model": self.options.sol_model,
                    "effort": self.options.sol_effort,
                    "input": self.input_items(),
                },
            )
            if "error" in turn_response:
                raise RuntimeError(error_text(turn_response["error"]))
            self.apply_turn_start(turn_response.get("result"))
            self.state.final_status = "in_progress"
            if self.options.mode == "off":
                self.state.switch_state = "disabled"
            elif not self.options.explore:
                self.state.switch_state = "not_explore"
            elif not self.switch_eligible():
                self.state.switch_state = "not_eligible"
            self.monitor()
            if self.state.final_status in {"completed", "interrupted", "failed"}:
                usage_response = self.request_sync(
                    "account/usage/read", {"threadId": self.state.thread_id}, timeout=10
                )
                if "error" not in usage_response:
                    self.state.account_usage = usage_response.get("result")
                    self.observe_account_usage_models(self.state.account_usage)
                    self.log("account_usage", usage=usage_response.get("result"))
                else:
                    self.state.errors.append(error_text(usage_response["error"]))
                    self.log("account_usage_error", error=usage_response["error"])
        except KeyboardInterrupt:
            self.state.user_cancelled = True
            self.state.final_status = "user_cancelled"
            self.state.switch_state = "cancelled"
            self.log("user_cancelled")
        except (OSError, RuntimeError, TimeoutError) as error:
            self.state.errors.append(str(error))
            self.state.final_status = "failed"
            self.log("run_failed", error=str(error), stderr=self.client.stderr_lines)
        finally:
            if self.state.completed_monotonic is None:
                self.state.completed_monotonic = time.monotonic()
            self.client.close()
        return self.result()

    def validate_models(self, response: Any) -> None:
        data = response.get("data") if isinstance(response, dict) else None
        if not isinstance(data, list):
            raise RuntimeError("model/list returned no data")
        models = {item.get("id"): item for item in data if isinstance(item, dict)}
        for model, effort in (
            (self.options.sol_model, self.options.sol_effort),
            (self.options.astra_model, self.options.astra_effort),
        ):
            entry = models.get(model)
            if not isinstance(entry, dict):
                raise RuntimeError(f"model is not available: {model}")
            efforts = entry.get("supportedReasoningEfforts")
            if not isinstance(efforts, list) or not any(
                isinstance(item, dict) and item.get("reasoningEffort") == effort
                for item in efforts
            ):
                raise RuntimeError(
                    f"reasoning effort is not available: {model}/{effort}"
                )

    def input_items(self) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        if self.options.explore:
            items.append(
                {
                    "type": "skill",
                    "name": "explore",
                    "path": str(self.options.skill_path),
                }
            )
            prompt = "$explore\n\n" + self.options.prompt
        else:
            prompt = self.options.prompt
        items.append({"type": "text", "text": prompt})
        return items

    def result(self) -> dict[str, Any]:
        credits = self.estimated_credits()
        if (
            self.options.max_estimated_credits is not None
            and credits is not None
            and credits > self.options.max_estimated_credits
            and self.state.final_status in {"completed", "interrupted"}
        ):
            self.state.final_status = "budget_exceeded"
        final_answer = "\n\n".join(
            self.state.agent_messages[item_id]
            for item_id in self.state.agent_message_order
            if self.state.agent_messages.get(item_id)
        )
        account_groups = None
        if isinstance(self.state.account_usage, dict):
            thread_usage = self.state.account_usage.get("threadUsage")
            if isinstance(thread_usage, dict):
                account_groups = thread_usage.get("groups")
        if (
            self.state.request_accepted
            and self.state.astra_execution_confirmed is None
            and isinstance(account_groups, list)
        ):
            self.state.astra_execution_confirmed = False
        elapsed = None
        if self.state.completed_monotonic is not None:
            elapsed = self.state.completed_monotonic - self.state.started_monotonic
        latest_usage = (
            self.state.usage_snapshots[-1]["token_usage"]
            if self.state.usage_snapshots
            else None
        )
        result = {
            "run_id": self.state.run_id,
            "status": self.state.final_status,
            "final_answer": final_answer,
            "thread_id": self.state.thread_id,
            "mode": self.options.mode,
            "explore": self.options.explore,
            "models": {
                "requested_start": self.options.sol_model,
                "requested_astra": self.options.astra_model,
                "observed": self.state.models_observed,
                "effective": self.state.effective_model,
                "effective_source": self.state.effective_model_source,
                "astra_execution_confirmed": self.state.astra_execution_confirmed,
            },
            "switch": {
                "state": self.state.switch_state,
                "condition_met": self.state.condition_met,
                "request_accepted": self.state.request_accepted,
                "count": self.state.switch_count,
                "fallback_steer_sent": self.state.fallback_steer_sent,
                "fallback_interrupt_sent": self.state.fallback_interrupt_sent,
                "fallback_interrupt_attempted": self.state.fallback_interrupt_attempted,
                "fallback_turn_started": self.state.fallback_turn_started,
            },
            "duration_seconds": round(elapsed, 3) if elapsed is not None else None,
            "estimated_active_seconds": round(elapsed, 3)
            if elapsed is not None
            else None,
            "turns": self.state.completed_turns,
            "token_usage": {
                "latest": latest_usage,
                "snapshots": self.state.usage_snapshots,
            },
            "estimated_usage_credits": credits,
            "account_usage": self.state.account_usage,
            "measurement_completeness": self.measurement_completeness(),
            "item_counts": self.state.item_counts,
            "errors": self.state.errors,
            "user_cancelled": self.state.user_cancelled,
            "timed_out": self.state.timed_out,
            "natural_completion": self.state.natural_completion,
            "stderr_tail": self.client.stderr_lines,
        }
        reserved = {
            "mode",
            "switch_state",
            "thread_id",
            "turn_id",
            "effective_model",
            "measurement_completeness",
        }
        self.log(
            "run_completed",
            **{
                key: value
                for key, value in result.items()
                if key not in reserved and key != "final_answer"
            },
        )
        return result


def run_router(options: RunOptions) -> dict[str, Any]:
    if options.mode not in {"off", "observe", "auto"}:
        raise ValueError("mode must be off, observe, or auto")
    if options.explore and not options.skill_path.is_file():
        raise FileNotFoundError(f"explore skill not found: {options.skill_path}")
    with JsonlLogger(options.log_path, options.run_id) as logger:
        result = RouterSession(options, logger).run()
    if options.answer_path is not None:
        options.answer_path.parent.mkdir(parents=True, exist_ok=True)
        options.answer_path.write_text(result["final_answer"], encoding="utf-8")
    return result


def config_path(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser()
    env_path = os.environ.get("CODEX_EXPLORE_ROUTER_CONFIG")
    if env_path:
        return Path(env_path).expanduser()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "codex" / "explore-router.toml"


def load_config(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("rb") as handle:
        data = tomllib.load(handle)
    values = data.get("router", data)
    return values if isinstance(values, dict) else {}


def router_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run an Explore task through Codex app-server."
    )
    parser.add_argument("--prompt")
    parser.add_argument("--prompt-file", type=Path)
    parser.add_argument("--explore", action="store_true")
    parser.add_argument("--skill-path", type=Path)
    parser.add_argument("--mode", choices=("off", "observe", "auto"))
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("--sol-model")
    parser.add_argument("--sol-effort")
    parser.add_argument("--astra-model")
    parser.add_argument("--astra-effort")
    parser.add_argument("--threshold-seconds", type=float)
    parser.add_argument("--switch-grace-seconds", type=float)
    parser.add_argument("--max-run-seconds", type=float)
    parser.add_argument("--max-estimated-credits", type=float)
    parser.add_argument("--codex-command")
    parser.add_argument("--log", dest="log_path", type=Path)
    parser.add_argument("--answer-file", type=Path)
    parser.add_argument("--config", type=str)
    return parser


def options_from_namespace(namespace: argparse.Namespace, prompt: str) -> RunOptions:
    values = load_config(config_path(namespace.config))

    def pick(name: str, default: Any) -> Any:
        command_value = getattr(namespace, name)
        return command_value if command_value is not None else values.get(name, default)

    return RunOptions(
        prompt=prompt,
        cwd=Path(pick("cwd", Path.cwd())).expanduser().resolve(),
        mode=pick("mode", "observe"),
        explore=bool(namespace.explore),
        skill_path=Path(pick("skill_path", DEFAULT_SKILL_PATH)).expanduser().resolve(),
        sol_model=pick("sol_model", DEFAULT_SOL_MODEL),
        sol_effort=pick("sol_effort", "medium"),
        astra_model=pick("astra_model", DEFAULT_ASTRA_MODEL),
        astra_effort=pick("astra_effort", "low"),
        threshold_seconds=float(pick("threshold_seconds", 60.0)),
        switch_grace_seconds=float(pick("switch_grace_seconds", 15.0)),
        max_run_seconds=float(pick("max_run_seconds", 1800.0)),
        max_estimated_credits=pick("max_estimated_credits", None),
        codex_command=pick("codex_command", "codex"),
        log_path=Path(pick("log_path", DEFAULT_LOG_PATH)).expanduser().resolve(),
        answer_path=(
            Path(namespace.answer_file).expanduser().resolve()
            if namespace.answer_file is not None
            else None
        ),
    )


def router_main(argv: list[str] | None = None) -> int:
    parser = router_parser()
    namespace = parser.parse_args(argv)
    if (namespace.prompt is None) == (namespace.prompt_file is None):
        parser.error("exactly one of --prompt or --prompt-file is required")
    if namespace.prompt_file is not None:
        try:
            prompt = namespace.prompt_file.read_text(encoding="utf-8")
        except OSError as error:
            parser.error(str(error))
    else:
        prompt = namespace.prompt
    try:
        options = options_from_namespace(namespace, prompt)
        result = run_router(options)
    except (FileNotFoundError, OSError, ValueError) as error:
        print(f"codex-explore-router: {error}", file=sys.stderr)
        return 1
    if result["final_answer"]:
        print(result["final_answer"])
    if result["status"] not in {"completed", "interrupted"}:
        return 1
    return 0


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
        "| 条件 | 実行数 | 成功数 | 完了時間中央値(秒) | credits中央値 | 切替実行確認 | 計測完全性 |",
        "| --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    summaries: dict[str, tuple[float | None, float | None]] = {}
    for key, condition in BENCHMARK_CONDITIONS.items():
        selected = [record for record in records if record.get("condition") == key]
        durations = [
            float(record["result"]["duration_seconds"])
            for record in selected
            if isinstance(
                record.get("result", {}).get("duration_seconds"), (int, float)
            )
        ]
        credits = [
            float(record["result"]["estimated_usage_credits"])
            for record in selected
            if isinstance(
                record.get("result", {}).get("estimated_usage_credits"), (int, float)
            )
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
        summaries[key] = (median_or_none(durations), median_or_none(credits))
        lines.append(
            f"| {key}: {condition.label} | {len(selected)} | "
            f"{sum(record.get('result', {}).get('status') in {'completed', 'interrupted'} for record in selected)} | "
            f"{format_metric(median_or_none(durations))} | {format_metric(median_or_none(credits))} | "
            f"{confirmed}/{len(selected)} | {', '.join(completeness) or 'unknown'} |"
        )
    base_duration, base_credits = summaries["A"]
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
        duration, credits = summaries[key]
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
    if namespace.max_total_seconds <= 0 or namespace.max_total_credits <= 0:
        parser.error("experiment budgets must be positive")
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
    except (OSError, ValueError) as error:
        parser.error(str(error))
    records: list[dict[str, Any]] = []
    started = time.monotonic()
    total_credits = 0.0
    events_path = output_dir / "events.jsonl"
    results_path = output_dir / "results.jsonl"
    for repetition in range(1, namespace.repetitions + 1):
        for condition in conditions:
            if time.monotonic() - started >= namespace.max_total_seconds:
                break
            if total_credits >= namespace.max_total_credits:
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
                max_run_seconds=namespace.max_run_seconds,
                codex_command=namespace.codex_command,
                log_path=events_path,
                answer_path=output_dir / "answers" / f"{run_id}.txt",
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
                break
        else:
            continue
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
    "AppServerClient",
    "BENCHMARK_CONDITIONS",
    "HANDOFF_PROMPT",
    "JsonlLogger",
    "RunOptions",
    "RunState",
    "RouterSession",
    "benchmark_main",
    "load_config",
    "parse_order",
    "run_router",
    "router_main",
]
