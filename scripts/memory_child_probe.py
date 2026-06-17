from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.memory_snapshot import _windows_working_set_private_mb


def mb(value: int) -> float:
    return round(value / 1024 / 1024, 1)


def memory_sample(pid: int) -> dict[str, float]:
    if os.name == "nt":
        sample = _windows_memory_sample(pid)
        if sample:
            return sample
    sample = _psutil_memory_sample(pid)
    if sample:
        return sample
    return {"rss": 0.0, "uss": 0.0, "private": 0.0}


def _psutil_memory_sample(pid: int) -> dict[str, float] | None:
    try:
        import psutil

        process = psutil.Process(pid)
        info = process.memory_info()
        sample = {"rss": mb(info.rss)}
        full = process.memory_full_info()
        sample["uss"] = mb(getattr(full, "uss", 0))
        sample["private"] = mb(getattr(full, "private", 0))
        return sample
    except Exception:
        return None


def _windows_memory_sample(pid: int) -> dict[str, float] | None:
    try:
        import ctypes
        from ctypes import wintypes

        class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
                ("PrivateUsage", ctypes.c_size_t),
            ]

        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        PROCESS_QUERY_INFORMATION = 0x0400
        PROCESS_VM_READ = 0x0010
        kernel32 = ctypes.windll.kernel32
        psapi = ctypes.windll.psapi
        handle = kernel32.OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
            False,
            int(pid),
        )
        if not handle:
            return None
        try:
            counters = PROCESS_MEMORY_COUNTERS_EX()
            counters.cb = ctypes.sizeof(counters)
            if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                return None
            return {
                "rss": mb(int(counters.WorkingSetSize)),
                "uss": 0.0,
                "private": mb(int(counters.PrivateUsage)),
                "ws_private": _windows_working_set_private_mb(handle, cache_key=int(pid)),
            }
        finally:
            kernel32.CloseHandle(handle)
    except Exception:
        return None


def main() -> int:
    env = os.environ.copy()
    env.setdefault("QROUNDEDFRAME_SMOKE_CLOSE_MS", "10500")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_PAGE", "about")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_OPEN_MS", "2600")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_CLOSE_MS", "7200")
    env.setdefault("QROUNDEDFRAME_SMOKE_CHILD_CLOSE_MODE", "window")
    proc = subprocess.Popen([sys.executable, "run.py"], cwd=ROOT, env=env)
    samples: list[tuple[str, float]] = []
    try:
        time.sleep(2.2)
        samples.append(("main_ready", memory_sample(proc.pid)))
        time.sleep(1.05)
        samples.append(("child_open", memory_sample(proc.pid)))
        time.sleep(2.2)
        samples.append(("child_open_late", memory_sample(proc.pid)))
        time.sleep(2.4)
        samples.append(("child_closed", memory_sample(proc.pid)))
        time.sleep(1.6)
        samples.append(("child_closed_late", memory_sample(proc.pid)))
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
    if len(samples) >= 2:
        base = samples[0][1]
        opened = samples[1][1]
        delta = {key: round(opened.get(key, 0.0) - base.get(key, 0.0), 1) for key in base}
        print(f"child_open_delta_mb={delta}")
    if len(samples) >= 3:
        base = samples[0][1]
        opened_late = samples[2][1]
        delta = {key: round(opened_late.get(key, 0.0) - base.get(key, 0.0), 1) for key in base}
        print(f"child_open_late_delta_mb={delta}")
    if len(samples) >= 5:
        base = samples[0][1]
        closed_late = samples[4][1]
        delta = {key: round(closed_late.get(key, 0.0) - base.get(key, 0.0), 1) for key in base}
        print(f"child_closed_late_delta_mb={delta}")
    return 0 if proc.returncode in (0, None) else int(proc.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
