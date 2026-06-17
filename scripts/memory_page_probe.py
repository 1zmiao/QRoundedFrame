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
    env["QROUNDEDFRAME_SMOKE_CLOSE_MS"] = "14000"
    sequence = os.environ.get(
        "QROUNDEDFRAME_MEMORY_PAGE_SEQUENCE",
        "settings,tools,update,about,home",
    )
    pages = [part.strip() for part in sequence.split(",") if part.strip()]
    env["QROUNDEDFRAME_SMOKE_PAGE_SEQUENCE"] = sequence
    env["QROUNDEDFRAME_SMOKE_PAGE_START_MS"] = "2600"
    env["QROUNDEDFRAME_SMOKE_PAGE_STEP_MS"] = "1500"
    proc = subprocess.Popen([sys.executable, "run.py"], cwd=ROOT, env=env)
    samples: list[tuple[str, dict[str, float]]] = []
    try:
        schedule = [("main_ready", 2.0)]
        for index, page in enumerate(pages):
            schedule.append((f"{page}_loaded", 2.1 if index == 0 else 1.5))
        schedule.append(("late", 3.0))
        for label, delay in schedule:
            time.sleep(delay)
            value = memory_sample(proc.pid)
            samples.append((label, value))
            print(f"{label}_mb={value}", flush=True)
        proc.wait(timeout=20)
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
    if samples:
        base = samples[0][1]
        for label, value in samples[1:]:
            delta = {key: round(value.get(key, 0.0) - base.get(key, 0.0), 1) for key in base}
            print(f"{label}_delta_mb={delta}")
    return 0 if proc.returncode in (0, None) else int(proc.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
