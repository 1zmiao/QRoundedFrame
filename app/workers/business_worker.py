from __future__ import annotations

import json
import sys
from typing import Any

from app.memory_snapshot import current_process_memory


def handle_request(request: dict[str, Any]) -> dict[str, Any]:
    method = str(request.get("method") or "")
    if method == "ping":
        return {"ok": True, "result": "pong"}
    if method == "memory_sample":
        return {"ok": True, "result": current_process_memory()}
    if method == "check_update":
        return {
            "ok": True,
            "result": {
                "message": "当前实验版未配置远程更新源。",
                "hasUpdate": False,
            },
        }
    return {"ok": False, "error": f"unknown method: {method}"}


def main() -> int:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            response = handle_request(request if isinstance(request, dict) else {})
        except Exception as exc:
            response = {"ok": False, "error": repr(exc)}
        sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
