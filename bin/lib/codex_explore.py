from __future__ import annotations

import argparse
import json
import selectors
import subprocess
import sys
import threading
import time
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
        self.process: subprocess.Popen[bytes] | None = None
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
    max_run_seconds: float = 1800.0
    codex_command: str = "codex"
    log_path: Path = DEFAULT_LOG_PATH
    answer_path: Path | None = None
    run_id: str = field(default_factory=lambda: uuid.uuid4().hex)


@dataclass
class TurnExecution:
    model: str
    allow_switch: bool
    turn_id: str | None = None
    started_monotonic: float | None = None
    outcome: str | None = None
    interrupt_sent: bool = False
    threshold_observed: bool = False
    important_items: dict[str, str] = field(default_factory=dict)
    agent_messages: dict[str, dict[str, Any]] = field(default_factory=dict)


@dataclass(frozen=True)
class TurnResult:
    turn_id: str | None
    model: str
    status: str
    switch: bool
    agent_messages: dict[str, dict[str, Any]]

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.turn_id,
            "model": self.model,
            "status": self.status,
            "switch": self.switch,
        }


@dataclass
class RunRecord:
    run_id: str
    thread_id: str | None = None
    parent_thread_id: str | None = None
    start_model: str | None = None
    turns: list[TurnResult] = field(default_factory=list)
    usage_by_thread: dict[str, dict[str, Any]] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    final_status: str = "not_started"
    user_cancelled: bool = False
    timed_out: bool = False
    started_monotonic: float = 0.0
    completed_monotonic: float | None = None


class RouterSession:
    def __init__(self, options: RunOptions, logger: JsonlLogger):
        self.options = options
        self.logger = logger
        self.record = RunRecord(options.run_id)
        self.client = AppServerClient(options.codex_command, options.cwd)
        self.active_turn: TurnExecution | None = None
        self.pending: dict[int, str] = {}

    def log(self, event: str, **fields: Any) -> None:
        turn = self.active_turn
        self.logger.write(
            event,
            mode=self.options.mode,
            thread_id=self.record.thread_id,
            turn_id=turn.turn_id if turn else None,
            model=turn.model if turn else None,
            **fields,
        )

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
            method = self.pending.pop(message["id"], None)
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
            self.record.errors.append(f"{method}: {message_text}")
            self.log("rpc_error", method=method, error=message["error"])
            return
        if method == "turn/interrupt":
            self.log("interrupt_response", result=message.get("result"))

    def parent_notification(self, params: dict[str, Any]) -> bool:
        return params.get("threadId") == self.record.thread_id

    def current_turn_notification(self, params: dict[str, Any]) -> bool:
        turn = self.active_turn
        return (
            turn is not None
            and self.parent_notification(params)
            and params.get("turnId") == turn.turn_id
        )

    def activate_turn(self, result: Any) -> None:
        turn = result.get("turn") if isinstance(result, dict) else None
        if not isinstance(turn, dict) or not isinstance(turn.get("id"), str):
            raise RuntimeError("turn/start returned no turn")
        active = self.active_turn
        if active is None:
            raise RuntimeError("turn/start returned without an active run")
        turn_id = turn["id"]
        if active.turn_id is None:
            active.turn_id = turn_id
        elif active.turn_id != turn_id:
            raise RuntimeError("turn/start returned an unexpected turn")
        if active.outcome is None and active.started_monotonic is None:
            active.started_monotonic = time.monotonic()
            self.log("turn_started", status=turn.get("status"))

    def handle_notification(self, method: str, params: dict[str, Any]) -> None:
        if method == "turn/started":
            if not self.parent_notification(params) or self.active_turn is None:
                return
            turn = params.get("turn")
            if not isinstance(turn, dict) or not isinstance(turn.get("id"), str):
                return
            if self.active_turn.turn_id not in (None, turn["id"]):
                return
            self.active_turn.turn_id = turn["id"]
            if self.active_turn.started_monotonic is None:
                self.active_turn.started_monotonic = time.monotonic()
                self.log("turn_started", status=turn.get("status"))
            return

        if method == "turn/completed":
            if not self.parent_notification(params) or self.active_turn is None:
                return
            turn = params.get("turn")
            if (
                isinstance(turn, dict)
                and turn.get("id") == self.active_turn.turn_id
                and isinstance(turn.get("status"), str)
            ):
                self.active_turn.outcome = turn["status"]
                self.log("turn_completed", status=turn["status"])
            return

        if method == "thread/tokenUsage/updated":
            thread_id = params.get("threadId")
            usage = params.get("tokenUsage")
            if isinstance(thread_id, str) and isinstance(usage, dict):
                self.usage_by_thread(thread_id)["token_usage"] = usage
                self.log("token_usage_updated", usage=usage)
            return

        if method == "item/agentMessage/delta":
            if not self.current_turn_notification(params):
                return
            item_id = params.get("itemId")
            delta = params.get("delta")
            if isinstance(item_id, str) and isinstance(delta, str):
                message = self.active_turn.agent_messages.setdefault(
                    item_id,
                    {"text": "", "turn_id": params["turnId"], "phase": None},
                )
                message["text"] += delta
            return

        if method in {"item/started", "item/completed"}:
            if not self.current_turn_notification(params):
                return
            self.handle_item(params.get("item"), started=method == "item/started")
            return

        if method == "error":
            self.record.errors.append(error_text(params))
            self.log("server_error", error=params)

    def usage_by_thread(self, thread_id: str) -> dict[str, Any]:
        return self.record.usage_by_thread.setdefault(thread_id, {})

    def handle_item(self, item: Any, *, started: bool) -> None:
        if not isinstance(item, dict):
            return
        item_id = item.get("id")
        item_type = item.get("type")
        if not isinstance(item_id, str):
            return
        if started:
            if not isinstance(item_type, str):
                return
            if item_type in IMPORTANT_ITEM_TYPES:
                self.active_turn.important_items[item_id] = item_type
            if item_type == "collabAgentToolCall":
                child_ids = item.get("receiverThreadIds")
                if isinstance(child_ids, list):
                    for child_id in child_ids:
                        if (
                            isinstance(child_id, str)
                            and child_id != self.record.thread_id
                        ):
                            self.usage_by_thread(child_id)
            if item_type == "subAgentActivity":
                child_id = item.get("agentThreadId")
                if isinstance(child_id, str) and child_id != self.record.thread_id:
                    self.usage_by_thread(child_id)
            self.log("item_started", item_id=item_id, item_type=item_type)
            return

        self.active_turn.important_items.pop(item_id, None)
        if item_type == "agentMessage":
            message = self.active_turn.agent_messages.setdefault(
                item_id,
                {"text": "", "turn_id": self.active_turn.turn_id, "phase": None},
            )
            if isinstance(item.get("text"), str):
                message["text"] = item["text"]
            if isinstance(item.get("phase"), str):
                message["phase"] = item["phase"]
        self.log("item_completed", item_id=item_id, item_type=item_type)

    def switch_eligible(self) -> bool:
        return (
            self.options.mode != "off"
            and self.options.explore
            and self.record.parent_thread_id is None
            and self.record.start_model == self.options.sol_model
        )

    def maybe_request_switch(self, turn: TurnExecution, now: float) -> bool:
        if (
            turn.interrupt_sent
            or not turn.allow_switch
            or self.record.user_cancelled
            or not self.switch_eligible()
            or turn.model != self.options.sol_model
            or turn.turn_id is None
            or turn.started_monotonic is None
            or now - turn.started_monotonic < self.options.threshold_seconds
            or turn.important_items
            or any(
                message.get("phase") == "final_answer"
                for message in turn.agent_messages.values()
            )
        ):
            return False
        if self.options.mode == "observe":
            if not turn.threshold_observed:
                turn.threshold_observed = True
                self.log("switch_condition_observed")
            return False
        if self.options.mode != "auto":
            return False
        self.request_async(
            "turn/interrupt",
            {"threadId": self.record.thread_id, "turnId": turn.turn_id},
        )
        turn.interrupt_sent = True
        self.log("interrupt_requested")
        return True

    def finish_turn(self, turn: TurnExecution) -> TurnResult:
        status = turn.outcome or "failed"
        result = TurnResult(
            turn_id=turn.turn_id,
            model=turn.model,
            status=status,
            switch=turn.interrupt_sent
            and status == "interrupted"
            and turn.allow_switch,
            agent_messages=dict(turn.agent_messages),
        )
        self.record.turns.append(result)
        self.active_turn = None
        return result

    def monitor_turn(self, turn: TurnExecution) -> TurnResult:
        while turn.outcome is None:
            now = time.monotonic()
            if now - self.record.started_monotonic >= self.options.max_run_seconds:
                self.record.timed_out = True
                turn.outcome = "timeout"
                self.log("run_timeout")
                break
            self.maybe_request_switch(turn, now)
            try:
                message = self.client.read(0.25)
            except EOFError as error:
                self.record.errors.append(str(error))
                turn.outcome = "server_closed"
                self.log("server_closed", stderr=self.client.stderr_lines)
                break
            except (OSError, RuntimeError) as error:
                self.record.errors.append(str(error))
                turn.outcome = "protocol_error"
                self.log("protocol_error", error=str(error))
                break
            if message is not None:
                self.dispatch(message)
        return self.finish_turn(turn)

    def run_turn(
        self,
        model: str,
        effort: str,
        input_items: list[dict[str, Any]],
        *,
        allow_switch: bool,
    ) -> TurnResult:
        turn = TurnExecution(model=model, allow_switch=allow_switch)
        self.active_turn = turn
        response = self.request_sync(
            "turn/start",
            {
                "threadId": self.record.thread_id,
                "model": model,
                "effort": effort,
                "input": input_items,
            },
        )
        if "error" in response:
            raise RuntimeError(error_text(response["error"]))
        self.activate_turn(response.get("result"))
        if turn.outcome is None:
            return self.monitor_turn(turn)
        return self.finish_turn(turn)

    def start_thread(self) -> None:
        response = self.request_sync(
            "thread/start",
            {
                "model": self.options.sol_model,
                "cwd": str(self.options.cwd),
                "sandbox": "read-only",
                "approvalPolicy": "never",
                "ephemeral": True,
            },
        )
        if "error" in response:
            raise RuntimeError(error_text(response["error"]))
        result = response.get("result")
        if not isinstance(result, dict):
            raise RuntimeError("thread/start returned no result")
        thread = result.get("thread")
        if not isinstance(thread, dict) or not isinstance(thread.get("id"), str):
            raise RuntimeError("thread/start returned no thread")
        self.record.thread_id = thread["id"]
        self.record.parent_thread_id = thread.get("parentThreadId")
        self.record.start_model = result.get("model") or self.options.sol_model
        self.usage_by_thread(thread["id"])
        self.log(
            "thread_started",
            parent_thread_id=self.record.parent_thread_id,
            configured_model=self.record.start_model,
        )

    def read_account_usage(self) -> None:
        for thread_id in list(self.record.usage_by_thread):
            try:
                response = self.request_sync(
                    "account/usage/read", {"threadId": thread_id}, timeout=10
                )
            except (OSError, RuntimeError, TimeoutError) as error:
                self.record.errors.append(f"account/usage/read: {error}")
                continue
            if "error" in response:
                self.record.errors.append(error_text(response["error"]))
                continue
            usage = response.get("result")
            if isinstance(usage, dict):
                reported = usage.get("threadUsage")
                reported_id = (
                    reported.get("threadId") if isinstance(reported, dict) else None
                )
                self.usage_by_thread(reported_id or thread_id)["account_usage"] = usage

    def run(self) -> dict[str, Any]:
        self.record.started_monotonic = time.monotonic()
        self.log("run_started", requested_model=self.options.sol_model)
        try:
            self.client.start()
            initialize = self.request_sync(
                "initialize",
                {
                    "clientInfo": {
                        "name": "codex-explore-router",
                        "version": ROUTER_VERSION,
                    },
                    "capabilities": {"experimentalApi": True},
                },
            )
            if "error" in initialize:
                raise RuntimeError(error_text(initialize["error"]))
            self.client.notify("initialized", {})
            models = self.request_sync(
                "model/list", {"includeHidden": True, "limit": 100}
            )
            if "error" in models:
                raise RuntimeError(error_text(models["error"]))
            self.validate_models(models.get("result"))
            self.start_thread()
            sol_result = self.run_turn(
                self.options.sol_model,
                self.options.sol_effort,
                self.input_items(),
                allow_switch=self.switch_eligible(),
            )
            if sol_result.switch:
                self.record.final_status = "in_progress"
                final_result = self.run_turn(
                    self.options.astra_model,
                    self.options.astra_effort,
                    [{"type": "text", "text": HANDOFF_PROMPT}],
                    allow_switch=False,
                )
            else:
                final_result = sol_result
            self.record.final_status = final_result.status
            self.record.completed_monotonic = time.monotonic()
            if final_result.status in {"completed", "interrupted", "failed"}:
                self.read_account_usage()
        except KeyboardInterrupt:
            self.record.user_cancelled = True
            self.record.final_status = "user_cancelled"
            self.log("user_cancelled")
        except (OSError, RuntimeError, TimeoutError) as error:
            self.record.errors.append(str(error))
            self.record.final_status = "failed"
            self.log("run_failed", error=str(error), stderr=self.client.stderr_lines)
        finally:
            if self.record.completed_monotonic is None:
                self.record.completed_monotonic = time.monotonic()
            self.client.close()
        return self.result()

    def validate_models(self, response: Any) -> None:
        data = response.get("data") if isinstance(response, dict) else None
        if not isinstance(data, list):
            raise RuntimeError("model/list returned no data")
        models = {item.get("id"): item for item in data if isinstance(item, dict)}
        required = [(self.options.sol_model, self.options.sol_effort)]
        if self.options.mode == "auto" and self.options.explore:
            required.append((self.options.astra_model, self.options.astra_effort))
        for model, effort in required:
            entry = models.get(model)
            if not isinstance(entry, dict):
                raise RuntimeError(f"model is not available: {model}")
            efforts = entry.get("supportedReasoningEfforts")
            if not isinstance(efforts, list) or not any(
                (item == effort)
                or (isinstance(item, dict) and item.get("reasoningEffort") == effort)
                for item in efforts
            ):
                raise RuntimeError(
                    f"reasoning effort is not available: {model}/{effort}"
                )

    def input_items(self) -> list[dict[str, Any]]:
        if not self.options.explore:
            return [{"type": "text", "text": self.options.prompt}]
        return [
            {
                "type": "skill",
                "name": "explore",
                "path": str(self.options.skill_path),
            },
            {"type": "text", "text": "$explore\n\n" + self.options.prompt},
        ]

    def estimated_credits(self) -> float | None:
        if not self.record.usage_by_thread:
            return None
        credits = 0
        for usage in self.record.usage_by_thread.values():
            account = usage.get("account_usage")
            thread_usage = (
                account.get("threadUsage") if isinstance(account, dict) else None
            )
            micros = (
                thread_usage.get("estimatedUsageCreditsMicros")
                if isinstance(thread_usage, dict)
                else None
            )
            if not isinstance(micros, int):
                return None
            credits += micros
        return credits / 1_000_000

    def measurement_completeness(self) -> str:
        has_tokens = bool(self.record.usage_by_thread) and all(
            isinstance(usage.get("token_usage"), dict)
            for usage in self.record.usage_by_thread.values()
        )
        has_credits = self.estimated_credits() is not None
        if has_tokens and has_credits:
            return "complete"
        if has_tokens or has_credits:
            return "partial"
        return "unknown"

    def final_answer(self) -> str:
        if self.active_turn is not None:
            messages = self.active_turn.agent_messages
        elif self.record.turns:
            messages = self.record.turns[-1].agent_messages
        else:
            messages = {}
        values = [message for message in messages.values() if message.get("text")]
        final = [
            message for message in values if message.get("phase") == "final_answer"
        ]
        return "\n\n".join(message["text"] for message in (final or values))

    def switch_details(self) -> dict[str, Any]:
        astra_started = any(
            turn.model == self.options.astra_model and turn.turn_id is not None
            for turn in self.record.turns
        ) or (
            self.active_turn is not None
            and self.active_turn.model == self.options.astra_model
            and self.active_turn.turn_id is not None
        )
        switch_requested = any(turn.switch for turn in self.record.turns)
        if astra_started:
            state = "switched"
        elif switch_requested:
            state = "switch_incomplete"
        elif self.options.mode == "off":
            state = "disabled"
        elif not self.options.explore:
            state = "not_explore"
        elif (
            self.record.parent_thread_id is not None
            or self.record.start_model != self.options.sol_model
        ):
            state = "not_eligible"
        else:
            state = "not_switched"
        return {
            "state": state,
            "interrupt_requested": switch_requested,
            "count": int(astra_started),
        }

    def result(self) -> dict[str, Any]:
        elapsed = None
        if self.record.completed_monotonic is not None:
            elapsed = self.record.completed_monotonic - self.record.started_monotonic
        parent_usage = self.record.usage_by_thread.get(self.record.thread_id or "", {})
        execution_models = [
            turn.model for turn in self.record.turns if turn.turn_id is not None
        ]
        if self.active_turn is not None and self.active_turn.turn_id is not None:
            execution_models.append(self.active_turn.model)
        switch = self.switch_details()
        astra_started = switch["count"] == 1
        result = {
            "run_id": self.record.run_id,
            "status": self.record.final_status,
            "final_answer": self.final_answer(),
            "thread_id": self.record.thread_id,
            "mode": self.options.mode,
            "explore": self.options.explore,
            "models": {
                "requested_start": self.options.sol_model,
                "requested_astra": self.options.astra_model,
                "started": self.record.start_model,
                "execution": execution_models,
                "astra_started": astra_started,
            },
            "switch": switch,
            "duration_seconds": round(elapsed, 3) if elapsed is not None else None,
            "token_usage": {
                "parent": parent_usage.get("token_usage"),
                "by_thread": self.record.usage_by_thread,
            },
            "estimated_usage_credits": self.estimated_credits(),
            "measurement_completeness": self.measurement_completeness(),
            "important_items": (
                self.active_turn.important_items if self.active_turn is not None else {}
            ),
            "turns": [turn.as_dict() for turn in self.record.turns],
            "errors": self.record.errors,
            "user_cancelled": self.record.user_cancelled,
            "timed_out": self.record.timed_out,
            "natural_completion": (
                self.record.final_status == "completed" and not astra_started
            ),
            "stderr_tail": self.client.stderr_lines,
        }
        self.log(
            "run_completed",
            status=result["status"],
            duration_seconds=result["duration_seconds"],
            token_usage=result["token_usage"]["parent"],
            estimated_usage_credits=result["estimated_usage_credits"],
            measurement_completeness=result["measurement_completeness"],
        )
        return result


def run_router(options: RunOptions) -> dict[str, Any]:
    if options.mode not in {"off", "observe", "auto"}:
        raise ValueError("mode must be off, observe, or auto")
    if options.max_run_seconds <= 0:
        raise ValueError("max_run_seconds must be positive")
    if options.threshold_seconds < 0:
        raise ValueError("threshold_seconds must not be negative")
    if options.explore and not options.skill_path.is_file():
        raise FileNotFoundError(f"explore skill not found: {options.skill_path}")
    with JsonlLogger(options.log_path, options.run_id) as logger:
        result = RouterSession(options, logger).run()
    if options.answer_path is not None:
        options.answer_path.parent.mkdir(parents=True, exist_ok=True)
        options.answer_path.write_text(result["final_answer"], encoding="utf-8")
    return result


def router_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run an Explore task through Codex app-server."
    )
    parser.add_argument("--prompt")
    parser.add_argument("--prompt-file", type=Path)
    parser.add_argument("--explore", action="store_true")
    parser.add_argument("--skill-path", type=Path, default=DEFAULT_SKILL_PATH)
    parser.add_argument("--mode", choices=("off", "observe", "auto"), default="observe")
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--sol-model", default=DEFAULT_SOL_MODEL)
    parser.add_argument("--sol-effort", default="medium")
    parser.add_argument("--astra-model", default=DEFAULT_ASTRA_MODEL)
    parser.add_argument("--astra-effort", default="low")
    parser.add_argument("--threshold-seconds", type=float, default=60.0)
    parser.add_argument("--max-run-seconds", type=float, default=1800.0)
    parser.add_argument("--codex-command", default="codex")
    parser.add_argument("--log", dest="log_path", type=Path, default=DEFAULT_LOG_PATH)
    parser.add_argument("--answer-file", type=Path)
    return parser


def options_from_namespace(namespace: argparse.Namespace, prompt: str) -> RunOptions:
    return RunOptions(
        prompt=prompt,
        cwd=namespace.cwd.expanduser().resolve(),
        mode=namespace.mode,
        explore=bool(namespace.explore),
        skill_path=namespace.skill_path.expanduser().resolve(),
        sol_model=namespace.sol_model,
        sol_effort=namespace.sol_effort,
        astra_model=namespace.astra_model,
        astra_effort=namespace.astra_effort,
        threshold_seconds=namespace.threshold_seconds,
        max_run_seconds=namespace.max_run_seconds,
        codex_command=namespace.codex_command,
        log_path=namespace.log_path.expanduser().resolve(),
        answer_path=(
            namespace.answer_file.expanduser().resolve()
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
        result = run_router(options_from_namespace(namespace, prompt))
    except (FileNotFoundError, OSError, ValueError) as error:
        print(f"codex-explore-router: {error}", file=sys.stderr)
        return 1
    if result["final_answer"]:
        print(result["final_answer"])
    return 0 if result["status"] in {"completed", "interrupted"} else 1


__all__ = [
    "AppServerClient",
    "DEFAULT_ASTRA_MODEL",
    "DEFAULT_SOL_MODEL",
    "HANDOFF_PROMPT",
    "JsonlLogger",
    "RunOptions",
    "RunRecord",
    "RouterSession",
    "TurnExecution",
    "TurnResult",
    "run_router",
    "router_main",
]
