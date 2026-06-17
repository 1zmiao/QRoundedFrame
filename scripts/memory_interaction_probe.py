from __future__ import annotations

import ctypes
import os
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

from memory_child_probe import memory_sample


ROOT = Path(__file__).resolve().parents[1]


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


def _window_class(hwnd: int) -> str:
    user32 = ctypes.windll.user32
    buffer = ctypes.create_unicode_buffer(260)
    user32.GetClassNameW(hwnd, buffer, 260)
    return buffer.value


def _windows_for_pid(pid: int) -> list[tuple[int, RECT, str, str]]:
    if os.name != "nt":
        return []
    user32 = ctypes.windll.user32
    windows: list[tuple[int, RECT, str, str]] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def enum_proc(hwnd, _lparam):
        window_pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(window_pid))
        if int(window_pid.value) != int(pid) or not user32.IsWindowVisible(hwnd):
            return True
        rect = RECT()
        if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
            return True
        width = rect.right - rect.left
        height = rect.bottom - rect.top
        if width < 260 or height < 160:
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        class_name = _window_class(hwnd)
        if "Shadow" in class_name or "shadow" in buffer.value.lower():
            return True
        windows.append((int(hwnd), rect, buffer.value, class_name))
        return True

    user32.EnumWindows(enum_proc, 0)
    return windows


def _main_window(pid: int) -> tuple[int, RECT, str, str] | None:
    candidates = _windows_for_pid(pid)
    if not candidates:
        return None
    titled = [item for item in candidates if item[2]]
    return max(titled or candidates, key=lambda item: (item[1].right - item[1].left) * (item[1].bottom - item[1].top))


def _click(hwnd: int, x: int, y: int) -> None:
    user32 = ctypes.windll.user32
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.08)
    user32.SetCursorPos(int(x), int(y))
    time.sleep(0.03)
    user32.mouse_event(0x0002, 0, 0, 0, 0)
    time.sleep(0.04)
    user32.mouse_event(0x0004, 0, 0, 0, 0)


def _press_escape() -> None:
    if os.name != "nt":
        return
    user32 = ctypes.windll.user32
    user32.keybd_event(0x1B, 0, 0, 0)
    time.sleep(0.03)
    user32.keybd_event(0x1B, 0, 0x0002, 0)


def _sample(label: str, pid: int, samples: list[tuple[str, dict[str, float]]]) -> None:
    value = memory_sample(pid)
    samples.append((label, value))
    print(f"{label}_mb={value}", flush=True)


def _click_title_menu(pid: int) -> bool:
    window = _main_window(pid)
    if window is None:
        return False
    hwnd, rect, _title, _class_name = window
    _click(hwnd, rect.left + 92, rect.top + 34)
    return True


def _click_palette(pid: int) -> bool:
    window = _main_window(pid)
    if window is None:
        return False
    hwnd, rect, _title, _class_name = window
    _click(hwnd, rect.right - 214, rect.top + 34)
    return True


def _click_theme(pid: int) -> bool:
    window = _main_window(pid)
    if window is None:
        return False
    hwnd, rect, _title, _class_name = window
    _click(hwnd, rect.right - 190, rect.top + 34)
    return True


def main() -> int:
    if os.name != "nt":
        print("memory_interaction_probe currently needs Win32 mouse/window APIs.")
        return 0

    env = os.environ.copy()
    env["QROUNDEDFRAME_SMOKE_CLOSE_MS"] = "22000"
    env["QROUNDEDFRAME_SMOKE_THEME_TOGGLE_MS"] = "12500"
    env["QROUNDEDFRAME_SMOKE_OPEN_MENU_MS"] = "2500"
    env["QROUNDEDFRAME_SMOKE_OPEN_PALETTE_MS"] = "5800"
    proc = subprocess.Popen([sys.executable, "run.py"], cwd=ROOT, env=env)
    samples: list[tuple[str, dict[str, float]]] = []
    try:
        time.sleep(1.8)
        _sample("main_ready", proc.pid, samples)

        time.sleep(1.35)
        _sample("title_menu_open", proc.pid, samples)
        _press_escape()
        time.sleep(1.15)
        _sample("title_menu_closed", proc.pid, samples)

        time.sleep(2.75)
        _sample("palette_open", proc.pid, samples)
        _press_escape()
        time.sleep(1.25)
        _sample("palette_closed", proc.pid, samples)

        time.sleep(1.0)
        _sample("before_theme_switch", proc.pid, samples)
        time.sleep(1.3)
        _sample("theme_switch_peak", proc.pid, samples)
        time.sleep(3.0)
        _sample("theme_switch_settled", proc.pid, samples)
        time.sleep(4.0)
        _sample("theme_switch_late", proc.pid, samples)

        proc.wait(timeout=30)
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
