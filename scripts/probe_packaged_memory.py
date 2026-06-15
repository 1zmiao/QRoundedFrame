from __future__ import annotations

import argparse
import ctypes
import os
import subprocess
import time
from ctypes import wintypes
from pathlib import Path


PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010


def mb(value: int) -> float:
    return round(float(value) / 1024.0 / 1024.0, 1)


def working_set_private_mb(pid: int) -> float:
    kernel32 = ctypes.windll.kernel32
    psapi = ctypes.windll.psapi

    class MEMORY_BASIC_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("BaseAddress", ctypes.c_void_p),
            ("AllocationBase", ctypes.c_void_p),
            ("AllocationProtect", wintypes.DWORD),
            ("RegionSize", ctypes.c_size_t),
            ("State", wintypes.DWORD),
            ("Protect", wintypes.DWORD),
            ("Type", wintypes.DWORD),
        ]

    class PSAPI_WORKING_SET_EX_BLOCK(ctypes.Structure):
        _fields_ = [("Flags", ctypes.c_size_t)]

    class PSAPI_WORKING_SET_EX_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("VirtualAddress", ctypes.c_void_p),
            ("VirtualAttributes", PSAPI_WORKING_SET_EX_BLOCK),
        ]

    class SYSTEM_INFO_UNION(ctypes.Union):
        _fields_ = [("dwOemId", wintypes.DWORD), ("w", ctypes.c_ushort * 2)]

    class SYSTEM_INFO(ctypes.Structure):
        _anonymous_ = ("u",)
        _fields_ = [
            ("u", SYSTEM_INFO_UNION),
            ("dwPageSize", wintypes.DWORD),
            ("lpMinimumApplicationAddress", ctypes.c_void_p),
            ("lpMaximumApplicationAddress", ctypes.c_void_p),
            ("dwActiveProcessorMask", ctypes.c_size_t),
            ("dwNumberOfProcessors", wintypes.DWORD),
            ("dwProcessorType", wintypes.DWORD),
            ("dwAllocationGranularity", wintypes.DWORD),
            ("wProcessorLevel", wintypes.WORD),
            ("wProcessorRevision", wintypes.WORD),
        ]

    handle = kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
        False,
        int(pid),
    )
    if not handle:
        return 0.0
    try:
        info = SYSTEM_INFO()
        kernel32.GetSystemInfo(ctypes.byref(info))
        page_size = max(4096, int(info.dwPageSize))
        max_address = int(info.lpMaximumApplicationAddress or 0)
        address = 0
        private_ws = 0
        entries: list[PSAPI_WORKING_SET_EX_INFORMATION] = []

        def flush() -> None:
            nonlocal private_ws, entries
            if not entries:
                return
            array_type = PSAPI_WORKING_SET_EX_INFORMATION * len(entries)
            array = array_type(*entries)
            size = ctypes.sizeof(array)
            if psapi.QueryWorkingSetEx(handle, ctypes.byref(array), wintypes.DWORD(size)):
                for entry in array:
                    flags = int(entry.VirtualAttributes.Flags)
                    valid = (flags & 0x1) != 0
                    shared = ((flags >> 15) & 0x1) != 0
                    if valid and not shared:
                        private_ws += page_size
            entries = []

        mbi = MEMORY_BASIC_INFORMATION()
        MEM_COMMIT = 0x1000
        PAGE_GUARD = 0x100
        PAGE_NOACCESS = 0x01
        while address < max_address:
            queried = kernel32.VirtualQueryEx(
                handle,
                ctypes.c_void_p(address),
                ctypes.byref(mbi),
                ctypes.sizeof(mbi),
            )
            if not queried:
                address += page_size
                continue
            region_size = int(mbi.RegionSize)
            if mbi.State == MEM_COMMIT and not (mbi.Protect & PAGE_GUARD) and not (mbi.Protect & PAGE_NOACCESS):
                pages = max(1, region_size // page_size)
                base = int(mbi.BaseAddress or address)
                for i in range(pages):
                    entries.append(PSAPI_WORKING_SET_EX_INFORMATION(ctypes.c_void_p(base + i * page_size), PSAPI_WORKING_SET_EX_BLOCK()))
                    if len(entries) >= 8192:
                        flush()
            address = int(mbi.BaseAddress or address) + max(region_size, page_size)
        flush()
        return mb(private_ws)
    finally:
        kernel32.CloseHandle(handle)


def find_runtime_process() -> int | None:
    output = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", "Get-Process QRoundedFrame -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"],
        text=True,
        errors="replace",
    )
    ids = [int(line.strip()) for line in output.splitlines() if line.strip().isdigit()]
    return ids[-1] if ids else None


def run_case(exe: Path, name: str, env_updates: dict[str, str], delay: float) -> tuple[str, float, Path | None]:
    release_dir = exe.parent
    env = os.environ.copy()
    env.update(env_updates)
    env["PATH"] = ""
    log_path = release_dir / "user_data" / "logs" / "cpp_ui_latest.log"
    try:
        log_path.unlink()
    except FileNotFoundError:
        pass
    proc = subprocess.Popen([str(exe)], cwd=release_dir, env=env)
    try:
        time.sleep(delay)
        pid = find_runtime_process()
        value = working_set_private_mb(pid) if pid else 0.0
        return name, value, log_path if log_path.exists() else None
    finally:
        subprocess.run(
            ["powershell", "-NoProfile", "-Command", "Get-Process QRoundedFrame -ErrorAction SilentlyContinue | Stop-Process -Force"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe packaged QRoundedFrame startup WS-Private memory.")
    parser.add_argument("--exe", default="dist/QRoundedFrame/QRoundedFrame.exe")
    parser.add_argument("--delay", type=float, default=7.0)
    args = parser.parse_args()

    exe = Path(args.exe).resolve()
    if not exe.exists():
        raise SystemExit(f"exe not found: {exe}")

    cases = [
        ("default", {}),
        ("software", {"QROUNDEDFRAME_RENDER_BACKEND": "software"}),
        ("opengl", {"QROUNDEDFRAME_RENDER_BACKEND": "opengl"}),
    ]
    for name, updates in cases:
        case_name, value, log_path = run_case(exe, name, updates, args.delay)
        print(f"{case_name:10s} ws_private={value:6.1f} MB")
        if log_path:
            lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
            for line in lines:
                if (
                    line.startswith("nativeFlavor=")
                    or line.startswith("renderBackend ")
                    or line.startswith("windowPolicy=")
                    or line.startswith("startup-memory ")
                ):
                    print(f"  {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
