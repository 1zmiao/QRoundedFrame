from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

from memory_child_probe import memory_sample


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    env = os.environ.copy()
    env.setdefault("QROUNDEDFRAME_SMOKE_CLOSE_MS", "14500")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_PAGE", "settings")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_OPEN_MS", "2200")
    env.setdefault("QROUNDEDFRAME_SMOKE_SECOND_CHILD_PAGE", "about")
    env.setdefault("QROUNDEDFRAME_SMOKE_SECOND_CHILD_OPEN_MS", "6200")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_CLOSE_MS", "9800")

    proc = subprocess.Popen([sys.executable, "run.py"], cwd=ROOT, env=env)
    checkpoints = [
        ("main_ready", 2.0),
        ("first_open_late", 3.8),
        ("second_open_late", 4.0),
        ("all_closed_late", 3.0),
    ]
    samples: list[tuple[str, dict[str, float]]] = []
    try:
        for name, delay in checkpoints:
            time.sleep(delay)
            samples.append((name, memory_sample(proc.pid)))
        proc.wait(timeout=8)
    except Exception:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        raise

    print(f"exit_code={proc.returncode}")
    print("note=rss is Windows working set; private is the real private commit to compare.")
    for name, value in samples:
        print(f"{name}_mb={value}")
    if samples:
        base = samples[0][1]
        for name, value in samples[1:]:
            delta = {key: round(value.get(key, 0.0) - base.get(key, 0.0), 1) for key in base}
            print(f"{name}_delta_mb={delta}")
    if len(samples) >= 3:
        first = samples[1][1]
        second = samples[2][1]
        delta = {key: round(second.get(key, 0.0) - first.get(key, 0.0), 1) for key in first}
        print(f"second_child_increment_mb={delta}")
    return 0 if proc.returncode in (0, None) else int(proc.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
