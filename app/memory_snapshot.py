from __future__ import annotations

import os
import sys
import time


_WS_PRIVATE_CACHE: dict[int, tuple[float, float]] = {}


def mb(value: int) -> float:
    return round(float(value) / 1024.0 / 1024.0, 1)


def current_process_memory(*, include_ws_private: bool = True) -> dict[str, float]:
    if os.name == "nt":
        sample = _windows_current_process_memory(include_ws_private=include_ws_private)
        if sample:
            return sample
    if sys.platform.startswith("linux"):
        sample = _linux_current_process_memory()
        if sample:
            return sample
    return {"rss": 0.0, "private": 0.0}


def _linux_current_process_memory() -> dict[str, float] | None:
    try:
        rollup = _read_linux_smaps_rollup()
        if rollup:
            rss = rollup.get("Rss", 0)
            private_clean = rollup.get("Private_Clean", 0)
            private_dirty = rollup.get("Private_Dirty", 0)
            private_hugetlb = rollup.get("Private_Hugetlb", 0)
            uss = private_clean + private_dirty + private_hugetlb
            pss = rollup.get("Pss", 0)
            return {
                "rss": round(rss / 1024.0, 1),
                "private": round(uss / 1024.0, 1),
                "uss": round(uss / 1024.0, 1),
                "pss": round(pss / 1024.0, 1),
                # The QML page uses the Windows name for a user-facing private
                # resident value. On Linux the closest honest equivalent is USS.
                "ws_private": round(uss / 1024.0, 1),
            }
        statm = PathLikeProcStatm.read()
        if statm:
            return statm
    except Exception:
        return None
    return None


def _read_linux_smaps_rollup() -> dict[str, int] | None:
    try:
        values: dict[str, int] = {}
        with open("/proc/self/smaps_rollup", "r", encoding="utf-8", errors="replace") as file:
            for line in file:
                if ":" not in line:
                    continue
                key, raw_value = line.split(":", 1)
                parts = raw_value.strip().split()
                if not parts:
                    continue
                try:
                    values[key] = int(parts[0])
                except ValueError:
                    continue
        return values
    except Exception:
        return None


class PathLikeProcStatm:
    @staticmethod
    def read() -> dict[str, float] | None:
        try:
            with open("/proc/self/statm", "r", encoding="utf-8", errors="replace") as file:
                parts = file.read().strip().split()
            if len(parts) < 2:
                return None
            page_size = os.sysconf("SC_PAGE_SIZE")
            rss = int(parts[1]) * int(page_size)
            return {
                "rss": mb(rss),
                "private": 0.0,
                "uss": 0.0,
                "pss": 0.0,
                "ws_private": 0.0,
            }
        except Exception:
            return None


def _windows_current_process_memory(*, include_ws_private: bool = True) -> dict[str, float] | None:
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

        kernel32 = ctypes.windll.kernel32
        psapi = ctypes.windll.psapi
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        PROCESS_QUERY_INFORMATION = 0x0400
        PROCESS_VM_READ = 0x0010
        kernel32.GetCurrentProcessId.restype = wintypes.DWORD
        kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel32.OpenProcess.restype = ctypes.c_void_p
        kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
        kernel32.CloseHandle.restype = wintypes.BOOL
        psapi.GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(PROCESS_MEMORY_COUNTERS_EX), wintypes.DWORD]
        psapi.GetProcessMemoryInfo.restype = wintypes.BOOL

        pid = int(kernel32.GetCurrentProcessId())
        handle = kernel32.OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
            False,
            pid,
        )
        if not handle:
            return None
        try:
            counters = PROCESS_MEMORY_COUNTERS_EX()
            counters.cb = ctypes.sizeof(counters)
            if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                return None
            ws_private = (
                _windows_working_set_private_mb(handle, cache_key=pid)
                if include_ws_private
                else 0.0
            )
            return {
                "rss": mb(int(counters.WorkingSetSize)),
                "private": mb(int(counters.PrivateUsage)),
                "ws_private": ws_private,
            }
        finally:
            kernel32.CloseHandle(handle)
    except Exception:
        return None


def _windows_working_set_private_mb(handle: int, cache_key: int = 0) -> float:
    global _WS_PRIVATE_CACHE
    now = time.monotonic()
    cached_at, cached_value = _WS_PRIVATE_CACHE.get(cache_key, (0.0, 0.0))
    if now - cached_at < 1.25:
        return cached_value
    try:
        import ctypes
        from ctypes import wintypes

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

        kernel32 = ctypes.windll.kernel32
        psapi = ctypes.windll.psapi

        kernel32.GetSystemInfo.argtypes = [ctypes.c_void_p]
        kernel32.VirtualQueryEx.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.POINTER(MEMORY_BASIC_INFORMATION),
            ctypes.c_size_t,
        ]
        kernel32.VirtualQueryEx.restype = ctypes.c_size_t
        psapi.QueryWorkingSetEx.argtypes = [ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD]
        psapi.QueryWorkingSetEx.restype = wintypes.BOOL

        class SYSTEM_INFO_UNION(ctypes.Union):
            _fields_ = [
                ("dwOemId", wintypes.DWORD),
                ("w", ctypes.c_ushort * 2),
            ]

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

        system_info = SYSTEM_INFO()
        kernel32.GetSystemInfo(ctypes.byref(system_info))
        page_size = max(4096, int(system_info.dwPageSize))
        max_addr = int(system_info.lpMaximumApplicationAddress or (2**47 if sys.maxsize > 2**32 else 2**31))

        MEM_COMMIT = 0x1000
        PAGE_GUARD = 0x100
        PAGE_NOACCESS = 0x01
        mbi = MEMORY_BASIC_INFORMATION()
        address = 0
        private_working_set = 0
        chunk_limit = 8192
        entries: list[PSAPI_WORKING_SET_EX_INFORMATION] = []

        def flush_entries() -> None:
            nonlocal private_working_set, entries
            if not entries:
                return
            array_type = PSAPI_WORKING_SET_EX_INFORMATION * len(entries)
            array = array_type(*entries)
            byte_size = ctypes.sizeof(array)
            if psapi.QueryWorkingSetEx(handle, ctypes.byref(array), byte_size):
                for item in array:
                    flags = int(item.VirtualAttributes.Flags)
                    valid = flags & 0x1
                    shared = (flags >> 15) & 0x1
                    if valid and not shared:
                        private_working_set += page_size
            entries = []

        while address < max_addr:
            result = kernel32.VirtualQueryEx(
                handle,
                ctypes.c_void_p(address),
                ctypes.byref(mbi),
                ctypes.sizeof(mbi),
            )
            if not result:
                address += page_size
                continue
            base = int(mbi.BaseAddress or address)
            region_size = int(mbi.RegionSize or page_size)
            protect = int(mbi.Protect)
            if int(mbi.State) == MEM_COMMIT and not (protect & PAGE_GUARD) and not (protect & PAGE_NOACCESS):
                end = min(base + region_size, max_addr)
                page = base
                while page < end:
                    entries.append(PSAPI_WORKING_SET_EX_INFORMATION(ctypes.c_void_p(page), PSAPI_WORKING_SET_EX_BLOCK(0)))
                    if len(entries) >= chunk_limit:
                        flush_entries()
                    page += page_size
            next_address = base + max(region_size, page_size)
            if next_address <= address:
                next_address = address + page_size
            address = next_address

        flush_entries()
        value = mb(private_working_set)
        _WS_PRIVATE_CACHE[cache_key] = (time.monotonic(), value)
        return value
    except Exception:
        return 0.0
