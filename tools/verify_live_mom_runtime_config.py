#!/usr/bin/env python3
"""Prove MOM 1.1.0's live authenticated runtime-config path."""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
import uuid

SYNC_URL = "https://ghdgrcwvpsxbarxmopdp.supabase.co/functions/v1/mom-sync"
BRAIN_URL = "https://ghdgrcwvpsxbarxmopdp.supabase.co/functions/v1/mom-brain"


def post(url: str, value: dict, headers: dict[str, str] | None = None) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(value).encode("utf-8"),
        headers={"content-type": "application/json", **(headers or {})},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{url} returned HTTP {error.code}: {detail}") from error


def main() -> int:
    installation = ""
    token = ""
    try:
        health = post(SYNC_URL, {"action": "health"})
        assert health.get("ok") is True, health
        assert int(health.get("version", 0)) >= 6, health
        assert health.get("raw_memory_location") == "device_only", health
        assert health.get("raw_chat_storage") is False, health

        device_id = f"mom-ci-runtime-{uuid.uuid4()}"
        registration = post(
            SYNC_URL,
            {
                "action": "register",
                "device_id": device_id,
                "platform": "github-actions",
                "app_version": "1.1.0-ci",
                "metadata": {"temporary": True},
            },
        )
        installation = registration["installation_id"]
        token = registration["token"]
        auth = {
            "x-mom-installation": installation,
            "x-mom-token": token,
        }
        result = post(SYNC_URL, {"action": "runtime_config"}, auth)
        config = result.get("config") or {}

        expected = {
            "release": "1.1.0",
            "runtime_authority": "supabase",
            "prompt_authority": "mom-brain",
            "model_authority": "mom-brain",
            "raw_memory_location": "device_only",
            "cloud_raw_chat_storage": False,
            "bundled_runtime_prompt_required": False,
            "bundled_repository_knowledge_required": False,
            "trademark_ui_assets": "device_bundled",
            "native_voice_runtime": "device_bundled",
        }
        for key, value in expected.items():
            assert config.get(key) == value, {"key": key, "config": config}
        assert result.get("min_app_version") == "1.1.0", result
        print("Live MOM 1.1.0 runtime config verified")
        return 0
    finally:
        if installation and token:
            try:
                post(
                    BRAIN_URL,
                    {"action": "unregister_test"},
                    {
                        "x-mom-installation": installation,
                        "x-mom-token": token,
                    },
                )
            except Exception as error:
                print(f"warning: disposable installation cleanup failed: {error}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
