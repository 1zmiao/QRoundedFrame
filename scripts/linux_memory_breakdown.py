from __future__ import annotations

import argparse
import os
from pathlib import Path


KEYS = (
    "Rss",
    "Pss",
    "Private_Clean",
    "Private_Dirty",
    "Private_Hugetlb",
    "Shared_Clean",
    "Shared_Dirty",
    "Swap",
)


def mb(kb: int) -> float:
    return round(kb / 1024.0, 1)


def read_rollup(pid: int) -> dict[str, int]:
    values: dict[str, int] = {}
    path = Path(f"/proc/{pid}/smaps_rollup")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        parts = raw.strip().split()
        if parts and parts[0].isdigit():
            values[key] = int(parts[0])
    return values


def read_status(pid: int) -> dict[str, int]:
    values: dict[str, int] = {}
    path = Path(f"/proc/{pid}/status")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        parts = raw.strip().split()
        if parts and parts[0].isdigit():
            values[key] = int(parts[0])
    return values


def cmdline(pid: int) -> str:
    data = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").strip()
    return data.decode("utf-8", errors="replace")


def find_candidates() -> list[int]:
    matches: list[int] = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            text = cmdline(pid).lower()
        except Exception:
            continue
        if "qroundedframe" in text or "frameless_pyside6_template" in text or "run.py" in text:
            matches.append(pid)
    return matches


def print_breakdown(pid: int) -> None:
    rollup = read_rollup(pid)
    status = read_status(pid)
    private_dirty = rollup.get("Private_Dirty", 0) + rollup.get("Private_Hugetlb", 0)
    uss = private_dirty + rollup.get("Private_Clean", 0)

    print(f"pid={pid}")
    print(f"cmd={cmdline(pid)}")
    print()
    print("smaps_rollup:")
    for key in KEYS:
        print(f"  {key:16s} {mb(rollup.get(key, 0)):8.1f} MB")
    print(f"  {'USS':16s} {mb(uss):8.1f} MB")
    print(f"  {'actual_private':16s} {mb(private_dirty):8.1f} MB")
    print()
    print("status:")
    for key in ("VmRSS", "RssAnon", "RssFile", "RssShmem", "VmSize"):
        print(f"  {key:16s} {mb(status.get(key, 0)):8.1f} MB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pid", nargs="?", type=int)
    args = parser.parse_args()
    pid = args.pid
    if pid is None:
        candidates = find_candidates()
        if not candidates:
            print("No QRoundedFrame/run.py process found.")
            return 1
        pid = candidates[0]
    print_breakdown(pid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
