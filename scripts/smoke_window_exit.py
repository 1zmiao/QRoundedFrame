from __future__ import annotations

import ctypes
import subprocess
import sys
import time
import os
from ctypes import wintypes
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / "user_data" / "native_smoke"
LOG_DIR.mkdir(parents=True, exist_ok=True)


EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
user32 = ctypes.windll.user32
user32.EnumWindows.argtypes = [EnumWindowsProc, wintypes.LPARAM]
user32.EnumWindows.restype = wintypes.BOOL
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostMessageW.restype = wintypes.BOOL
user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetWindowRect.restype = wintypes.BOOL
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.SetForegroundWindow.restype = wintypes.BOOL
user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
user32.SetCursorPos.restype = wintypes.BOOL
user32.mouse_event.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.ULONG]
user32.mouse_event.restype = None


def visible_windows_for_pid(pid: int) -> list[tuple[int, str]]:
    handles: list[tuple[int, str]] = []

    @EnumWindowsProc
    def callback(hwnd, _lparam):
        window_pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(window_pid))
        if int(window_pid.value) == int(pid) and user32.IsWindowVisible(hwnd):
            title = ctypes.create_unicode_buffer(260)
            user32.GetWindowTextW(hwnd, title, 260)
            if title.value.strip():
                handles.append((int(hwnd), title.value.strip()))
        return True

    user32.EnumWindows(callback, 0)
    return handles


def main() -> int:
    stdout_path = LOG_DIR / "exit_stdout.log"
    stderr_path = LOG_DIR / "exit_stderr.log"
    for path in (stdout_path, stderr_path):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    with stdout_path.open("w", encoding="utf-8", errors="replace") as stdout, stderr_path.open(
        "w", encoding="utf-8", errors="replace"
    ) as stderr:
        env = os.environ.copy()
        use_internal_close = os.environ.get("QROUNDEDFRAME_SMOKE_EXTERNAL_CLOSE", "").strip().lower() not in {"1", "true", "yes"}
        pure_external_close = os.environ.get("QROUNDEDFRAME_SMOKE_PURE_EXTERNAL_CLOSE", "").strip().lower() in {"1", "true", "yes"}
        if pure_external_close:
            env.pop("QROUNDEDFRAME_SMOKE_CLOSE_MS", None)
        else:
            env["QROUNDEDFRAME_SMOKE_CLOSE_MS"] = os.environ.get(
                "QROUNDEDFRAME_SMOKE_CLOSE_MS",
                "1500" if use_internal_close else "600000",
            )
        if pure_external_close:
            use_internal_close = False
        proc = subprocess.Popen(
            [sys.executable, "run.py"],
            cwd=ROOT,
            stdout=stdout,
            stderr=stderr,
            text=True,
            env=env,
        )

        handles: list[tuple[int, str]] = []
        deadline = time.monotonic() + 12.0
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            handles = visible_windows_for_pid(proc.pid)
            if handles:
                break
            time.sleep(0.2)

        click_points: list[tuple[int, int, int, int, int, int]] = []
        for hwnd, _title in ([] if use_internal_close else handles):
            rect = wintypes.RECT()
            if user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect)):
                user32.SetForegroundWindow(wintypes.HWND(hwnd))
                time.sleep(0.35)
                x = rect.right - 17
                y = rect.top + 21
                click_points.append((hwnd, rect.left, rect.top, rect.right, rect.bottom, x))
                for _ in range(2):
                    user32.SetCursorPos(x, y)
                    user32.mouse_event(0x0002, 0, 0, 0, 0)  # MOUSEEVENTF_LEFTDOWN
                    time.sleep(0.06)
                    user32.mouse_event(0x0004, 0, 0, 0, 0)  # MOUSEEVENTF_LEFTUP
                    time.sleep(0.25)
                    if proc.poll() is not None:
                        break
                if proc.poll() is None:
                    user32.PostMessageW(wintypes.HWND(hwnd), 0x0112, 0xF060, 0)  # WM_SYSCOMMAND / SC_CLOSE

        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)

    stderr_text = stderr_path.read_text(encoding="utf-8", errors="replace") if stderr_path.exists() else ""
    stdout_text = stdout_path.read_text(encoding="utf-8", errors="replace") if stdout_path.exists() else ""
    print(f"exit_code={proc.returncode}")
    print(f"window_count={len(handles)}")
    for hwnd, title in handles:
        print(f"window=0x{hwnd:x} {title}")
    for hwnd, left, top, right, bottom, x in click_points:
        print(f"clicked=0x{hwnd:x} rect={left},{top},{right},{bottom} point={x},{top + 21}")
    if stderr_text.strip():
        print("--- stderr ---")
        print(stderr_text.strip())
    if stdout_text.strip():
        print("--- stdout ---")
        print(stdout_text.strip())
    if "QThreadStorage:" in stderr_text or "QDxgiVSyncService" in stderr_text:
        return 3
    if "CreateWindowEx failed" in stderr_text or "Failed to create platform window" in stderr_text:
        return 2
    return 0 if proc.returncode in (0, None) else int(proc.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
