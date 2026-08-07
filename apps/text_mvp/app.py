#!/usr/bin/env python3
"""MOM text MVP.

Zero third-party Python dependencies. Serves a small browser UI, talks to any
OpenAI-compatible chat-completions endpoint, and persists conversations locally
with optional Supabase mirroring.
"""

from __future__ import annotations

import json
import os
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

APP_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = APP_DIR.parent.parent
STATIC_DIR = APP_DIR / "static"
DATA_DIR = APP_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)
TRANSCRIPT_FILE = DATA_DIR / "conversations.jsonl"
PROMPT_FILE = REPO_ROOT / "core_llm" / "mom_identity" / "runtime_prompt.md"


def load_dotenv() -> None:
    path = APP_DIR / ".env"
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


load_dotenv()

HOST = os.getenv("MOM_HOST", "127.0.0.1")
PORT = int(os.getenv("MOM_PORT", "8787"))
API_BASE = os.getenv("MOM_API_BASE", "http://127.0.0.1:8080/v1").rstrip("/")
API_KEY = os.getenv("MOM_API_KEY", "")
MODEL = os.getenv("MOM_MODEL", "").strip()
TEMPERATURE = float(os.getenv("MOM_TEMPERATURE", "0.72"))
MAX_HISTORY = int(os.getenv("MOM_MAX_HISTORY", "30"))
SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")

SYSTEM_PROMPT = PROMPT_FILE.read_text(encoding="utf-8") if PROMPT_FILE.exists() else (
    "You are MOM, a persistent personal intelligence. Be useful, truthful, warm, "
    "opinionated when evidence supports it, and never invent memories or actions."
)

# In-memory cache is only a speed layer. Every turn is also written to JSONL.
SESSIONS: dict[str, list[dict[str, str]]] = {}


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False).encode("utf-8")


def http_json(
    method: str,
    url: str,
    payload: Any | None = None,
    headers: dict[str, str] | None = None,
    timeout: int = 120,
) -> tuple[int, Any]:
    body = None if payload is None else json_bytes(payload)
    request_headers = {"Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    req = urllib.request.Request(url, data=body, headers=request_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            if not raw:
                return resp.status, None
            return resp.status, json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            detail: Any = json.loads(raw)
        except json.JSONDecodeError:
            detail = raw
        raise RuntimeError(f"HTTP {exc.code} from {url}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Could not reach {url}: {exc.reason}") from exc


def discover_model() -> str:
    if MODEL:
        return MODEL
    headers = {}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"
    try:
        _, data = http_json("GET", f"{API_BASE}/models", headers=headers, timeout=8)
        models = data.get("data", []) if isinstance(data, dict) else []
        if models:
            candidate = models[0].get("id")
            if candidate:
                return str(candidate)
    except Exception:
        pass
    raise RuntimeError(
        "No model is configured. Set MOM_MODEL in apps/text_mvp/.env. "
        "The default endpoint is llama.cpp at http://127.0.0.1:8080/v1."
    )


def append_local_event(session_id: str, role: str, content: str, metadata: dict[str, Any] | None = None) -> None:
    record = {
        "session_id": session_id,
        "role": role,
        "content": content,
        "metadata": metadata or {},
        "created_at": time.time(),
    }
    with TRANSCRIPT_FILE.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def supabase_headers() -> dict[str, str]:
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Prefer": "return=minimal",
    }


def supabase_enabled() -> bool:
    return bool(SUPABASE_URL and SUPABASE_KEY)


def mirror_session(session_id: str, model_name: str) -> None:
    if not supabase_enabled():
        return
    payload = {
        "id": session_id,
        "title": "MOM text conversation",
        "model_provider": API_BASE,
        "model_name": model_name,
        "device_id": "text_mvp",
    }
    try:
        http_json(
            "POST",
            f"{SUPABASE_URL}/rest/v1/mom_chat_sessions",
            payload,
            headers=supabase_headers(),
            timeout=12,
        )
    except Exception as exc:
        print(f"[MOM] Supabase session mirror skipped: {exc}")


def mirror_message(session_id: str, role: str, content: str, metadata: dict[str, Any] | None = None) -> None:
    if not supabase_enabled():
        return
    payload = {
        "session_id": session_id,
        "role": role,
        "content": content,
        "metadata": metadata or {},
    }
    try:
        http_json(
            "POST",
            f"{SUPABASE_URL}/rest/v1/mom_chat_messages",
            payload,
            headers=supabase_headers(),
            timeout=12,
        )
    except Exception as exc:
        print(f"[MOM] Supabase message mirror skipped: {exc}")


def remember_turn(session_id: str, role: str, content: str, metadata: dict[str, Any] | None = None) -> None:
    SESSIONS.setdefault(session_id, []).append({"role": role, "content": content})
    append_local_event(session_id, role, content, metadata)
    mirror_message(session_id, role, content, metadata)


def chat(session_id: str, user_text: str) -> dict[str, Any]:
    if not user_text.strip():
        raise ValueError("Message is empty.")

    model_name = discover_model()
    is_new = session_id not in SESSIONS
    history = SESSIONS.setdefault(session_id, [])
    if is_new:
        mirror_session(session_id, model_name)

    remember_turn(session_id, "user", user_text)
    recent = history[-MAX_HISTORY:]
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, *recent]

    headers = {}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"

    payload = {
        "model": model_name,
        "messages": messages,
        "temperature": TEMPERATURE,
        "stream": False,
    }
    _, data = http_json(
        "POST",
        f"{API_BASE}/chat/completions",
        payload,
        headers=headers,
        timeout=300,
    )

    try:
        answer = data["choices"][0]["message"]["content"]
    except Exception as exc:
        raise RuntimeError(f"Model returned an unexpected response: {data}") from exc

    if not isinstance(answer, str) or not answer.strip():
        raise RuntimeError("Model returned an empty response.")

    metadata = {"model": model_name, "api_base": API_BASE}
    remember_turn(session_id, "assistant", answer, metadata)
    return {"session_id": session_id, "message": answer, "model": model_name}


class Handler(BaseHTTPRequestHandler):
    server_version = "MOMText/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[MOM] {self.address_string()} - {fmt % args}")

    def send_json(self, status: int, payload: Any) -> None:
        body = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def serve_file(self, path: pathlib.Path, content_type: str) -> None:
        if not path.exists():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        route = urllib.parse.urlparse(self.path).path
        if route == "/":
            self.serve_file(STATIC_DIR / "index.html", "text/html; charset=utf-8")
            return
        if route == "/health":
            self.send_json(HTTPStatus.OK, {
                "ok": True,
                "name": "MOM",
                "api_base": API_BASE,
                "model_configured": bool(MODEL),
                "supabase_configured": supabase_enabled(),
            })
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        route = urllib.parse.urlparse(self.path).path
        if route != "/api/chat":
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length).decode("utf-8"))
            session_id = str(data.get("session_id") or uuid.uuid4())
            # Validate UUID early so the Supabase UUID column receives a valid value.
            uuid.UUID(session_id)
            message = str(data.get("message") or "")
            result = chat(session_id, message)
            self.send_json(HTTPStatus.OK, result)
        except ValueError as exc:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception as exc:
            self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(exc)})


def main() -> None:
    print("MOM text MVP")
    print(f"UI:        http://{HOST}:{PORT}")
    print(f"Model API: {API_BASE}")
    print(f"Identity:  {PROMPT_FILE}")
    print(f"Supabase:  {'configured' if supabase_enabled() else 'local transcript fallback'}")
    print("Press Ctrl+C to stop.")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[MOM] stopped")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
