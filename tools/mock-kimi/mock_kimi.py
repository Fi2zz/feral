#!/usr/bin/env python3
"""Kimi（OpenAI 兼容）联调用的假服务。

为什么必须是 SSE 而不是普通 JSON：Swiftus 的 OpenAiCompatibleProvider 连非流式的
chat() 也走流式端点（请求体里 stream 恒为 true），期望的是 data: {...} 帧 + data: [DONE]。
回一个普通 JSON 体它会当成 0 个增量，得到空回答。

用法：
    python3 tools/mock-kimi/mock_kimi.py              # 127.0.0.1:8099
    python3 tools/mock-kimi/mock_kimi.py --port 9000
    python3 tools/mock-kimi/mock_kimi.py --fail 401   # 验错误提示，不静默失败
    python3 tools/mock-kimi/mock_kimi.py --slow 0.3   # 慢速分片，看流式装配

把 App 指过来（模拟器）：
    make run-mock
真机得用 Mac 的局域网地址：make run-mock HOST=http://192.168.1.5:8099
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    server_version = "mock-kimi/1"

    # ---- 路由 ----

    def do_POST(self) -> None:
        body = self._read_json()
        if self.path.rstrip("/").endswith("/chat/completions"):
            self._chat(body)
            return
        self._error(404, f"没有这个端点：{self.path}")

    def do_GET(self) -> None:
        if self.path.rstrip("/").endswith("/models"):
            payload = {"object": "list", "data": [{"id": self.server.model, "object": "model"}]}
            self._send_json(200, payload)
            return
        self._error(404, f"没有这个端点：{self.path}")

    # ---- 对话 ----

    def _chat(self, body: dict) -> None:
        self._log_request(body)
        # 定点触发错误：把 baseUrl 指到 .../v1/unauthorized，最终路径就会带上这段。
        if "/unauthorized/" in self.path:
            self._error(401, "mock 的 401：这把 Key 不认。")
            return
        if self.server.fail_status:
            self._error(
                self.server.fail_status,
                "mock 故意返回的错误，用来验 App 会不会把原因显示出来。",
            )
            return
        self._send_sse(self._reply(body))

    def _reply(self, body: dict) -> str:
        messages = body.get("messages") or []
        system = next((m.get("content", "") for m in messages if m.get("role") == "system"), "")
        user = next((m.get("content", "") for m in reversed(messages) if m.get("role") == "user"), "")
        history = [m for m in messages if m.get("role") in ("user", "assistant")][:-1]

        asked = user.split("\n")[-1][:60]
        session = self.headers.get("x-opencode-session") or "（无）"
        has_search = "<search_results>" in user

        lines = [
            "（mock）收到了。",
            f"reasoning_effort：{body.get('reasoning_effort', '（无）')}。",
            f"system {len(system)} 字。",
            f"x-opencode-session：{session}。",
            f"搜索 {'✓' if has_search else '✗'}。",
            f"历史消息 {len(history)} 条。这句是：{asked}",
        ]
        return "\n".join(lines)

    def _send_sse(self, text: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        # 思考增量先行：客户端的 reasoning_content 装配也走一遍（DeepSeek 思考模式同链路）。
        for piece in _chunks("（mock）先理一下思路。"):
            self._write_chunk({"delta": {"reasoning_content": piece}})

        # 按行切片发，模拟真实分片，让客户端的增量装配真的走一遍。
        for line in text.split("\n"):
            for piece in _chunks(line):
                self._write_chunk({"delta": {"content": piece}})
                if self.server.slow:
                    time.sleep(self.server.slow)
            self._write_chunk({"delta": {"content": "\n"}})

        self._write_chunk({"delta": {}, "finish_reason": "stop"}, usage={
            "prompt_tokens": 1234,
            "completion_tokens": 56,
            "total_tokens": 1290,
        })
        self._raw("data: [DONE]\n\n")

    def _write_chunk(self, choice: dict, usage: dict | None = None) -> None:
        payload: dict = {
            "id": "chatcmpl-mock",
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": self.server.model,
            "choices": [{"index": 0, **choice}],
        }
        if usage is not None:
            payload["usage"] = usage
        self._raw("data: " + json.dumps(payload, ensure_ascii=False) + "\n\n")

    # ---- 日志与工具 ----

    def _log_request(self, body: dict) -> None:
        messages = body.get("messages") or []
        print(
            f"\n→ POST {self.path}  model={body.get('model')}  stream={body.get('stream')}"
            f"  reasoning_effort={body.get('reasoning_effort', '（无）')}",
            file=sys.stderr,
        )
        extra = [key for key in body if key not in {"model", "messages", "stream", "stream_options", "reasoning_effort"}]
        if extra:
            print(f"  其他顶层字段：{extra}", file=sys.stderr)
        print(f"  Authorization: {self.headers.get('Authorization', '(无)')[:24]}…", file=sys.stderr)
        print(f"  {len(messages)} 条消息：{[m.get('role') for m in messages]}", file=sys.stderr)
        for message in messages:
            if message.get("role") != "user":
                continue
            print("  ── user 全文 ──", file=sys.stderr)
            for line in message.get("content", "").split("\n"):
                print(f"  │ {line}", file=sys.stderr)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}

    def _raw(self, text: str) -> None:
        self.wfile.write(text.encode("utf-8"))
        self.wfile.flush()

    def _send_json(self, status: int, payload: dict) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _error(self, status: int, message: str) -> None:
        # OpenAI 风格的错误体：Swiftus 会把整个 body 作为错误原因抛出来。
        print(f"  ! 返回 {status}：{message}", file=sys.stderr)
        self._send_json(status, {"error": {"message": message, "type": "mock_error", "code": status}})

    def log_message(self, fmt: str, *args) -> None:
        return  # 默认那行太吵，日志走 _log_request


def _chunks(line: str, size: int = 12) -> list[str]:
    return [line[i:i + size] for i in range(0, len(line), size)] or [""]


def main() -> None:
    parser = argparse.ArgumentParser(description="Kimi 联调假服务")
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--model", default="kimi-k3", help="只是回显用的模型名，不校验")
    parser.add_argument("--fail", type=int, default=0, help="固定返回这个 HTTP 状态码")
    parser.add_argument("--slow", type=float, default=0, help="每片之间的秒数")
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.model = args.model
    server.fail_status = args.fail
    server.slow = args.slow

    print(f"mock-kimi 在 http://{args.host}:{args.port}/v1（model={args.model}）", file=sys.stderr)
    if args.fail:
        print(f"注意：固定返回 {args.fail}，只用来验错误提示", file=sys.stderr)
    print("App 指过来：make run-mock", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye", file=sys.stderr)


if __name__ == "__main__":
    main()
