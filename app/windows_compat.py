from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes


class RTL_OSVERSIONINFOW(ctypes.Structure):
    _fields_ = [
        ("dwOSVersionInfoSize", wintypes.ULONG),
        ("dwMajorVersion", wintypes.ULONG),
        ("dwMinorVersion", wintypes.ULONG),
        ("dwBuildNumber", wintypes.ULONG),
        ("dwPlatformId", wintypes.ULONG),
        ("szCSDVersion", wintypes.WCHAR * 128),
    ]


def windows_build_number() -> int:
    if sys.platform != "win32":
        return 0
    info = RTL_OSVERSIONINFOW()
    info.dwOSVersionInfoSize = ctypes.sizeof(info)
    try:
        status = ctypes.windll.ntdll.RtlGetVersion(ctypes.byref(info))
        if status == 0:
            return int(info.dwBuildNumber)
    except Exception:
        pass
    try:
        return int(sys.getwindowsversion().build)
    except Exception:
        return 0


def is_windows_11_or_newer() -> bool:
    return sys.platform == "win32" and windows_build_number() >= 22000


def use_custom_window_shadow() -> bool:
    return sys.platform == "win32" and not is_windows_11_or_newer()
