from __future__ import annotations

import argparse
import ctypes
import os
import shutil
import struct
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "user_data" / "native_smoke" / "screens"

EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

user32.EnumWindows.argtypes = [EnumWindowsProc, wintypes.LPARAM]
user32.EnumWindows.restype = wintypes.BOOL
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetClassNameW.restype = ctypes.c_int
user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetWindowRect.restype = wintypes.BOOL
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.SetForegroundWindow.restype = wintypes.BOOL
user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
user32.SetCursorPos.restype = wintypes.BOOL
user32.mouse_event.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.ULONG]
user32.mouse_event.restype = None
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostMessageW.restype = wintypes.BOOL
user32.SendMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.SendMessageW.restype = ctypes.c_ssize_t
user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
user32.ShowWindow.restype = wintypes.BOOL
user32.GetDC.argtypes = [wintypes.HWND]
user32.GetDC.restype = wintypes.HDC
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
user32.ReleaseDC.restype = ctypes.c_int

gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.BitBlt.argtypes = [
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.DWORD,
]
gdi32.BitBlt.restype = wintypes.BOOL
gdi32.GetDIBits.argtypes = [
    wintypes.HDC,
    wintypes.HBITMAP,
    wintypes.UINT,
    wintypes.UINT,
    ctypes.c_void_p,
    ctypes.c_void_p,
    wintypes.UINT,
]
gdi32.GetDIBits.restype = ctypes.c_int
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteObject.restype = wintypes.BOOL
gdi32.DeleteDC.argtypes = [wintypes.HDC]
gdi32.DeleteDC.restype = wintypes.BOOL

MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
WM_SYSCOMMAND = 0x0112
SC_CLOSE = 0xF060
WM_NCHITTEST = 0x0084
WM_NCLBUTTONDOWN = 0x00A1
HTRIGHT = 11
HTBOTTOM = 15
HTBOTTOMRIGHT = 17
SRCCOPY = 0x00CC0020
DIB_RGB_COLORS = 0
BI_RGB = 0
SW_HIDE = 0
SHADOW_CLASS = "FramelessNativeShadowWindow"


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [
        ("bmiHeader", BITMAPINFOHEADER),
        ("bmiColors", wintypes.DWORD * 3),
    ]


def window_class(hwnd: int) -> str:
    buffer = ctypes.create_unicode_buffer(260)
    user32.GetClassNameW(wintypes.HWND(hwnd), buffer, 260)
    return buffer.value


def windows_for_pid(pid: int, visible_only: bool = True) -> list[tuple[int, str, str]]:
    handles: list[tuple[int, str, str]] = []

    @EnumWindowsProc
    def callback(hwnd, _lparam):
        window_pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(window_pid))
        if int(window_pid.value) != int(pid):
            return True
        if visible_only and not user32.IsWindowVisible(hwnd):
            return True
        title = ctypes.create_unicode_buffer(260)
        user32.GetWindowTextW(hwnd, title, 260)
        handles.append((int(hwnd), title.value.strip(), window_class(int(hwnd))))
        return True

    user32.EnumWindows(callback, 0)
    return handles


def visible_windows_for_pid(pid: int) -> list[tuple[int, str]]:
    windows = []
    for hwnd, title, cls in windows_for_pid(pid):
        if title and cls != SHADOW_CLASS:
            windows.append((hwnd, title))
    return windows


def hide_shadow_windows(pid: int) -> int:
    count = 0
    for hwnd, _title, cls in windows_for_pid(pid, visible_only=False):
        if cls == SHADOW_CLASS:
            user32.ShowWindow(wintypes.HWND(hwnd), SW_HIDE)
            count += 1
    return count


def rect_for(hwnd: int) -> tuple[int, int, int, int]:
    rect = wintypes.RECT()
    if not user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect)):
        raise RuntimeError(f"GetWindowRect failed for 0x{hwnd:x}")
    return int(rect.left), int(rect.top), int(rect.right), int(rect.bottom)


def wait_for_windows(pid: int, count: int = 1, timeout: float = 10.0) -> list[tuple[int, str]]:
    deadline = time.monotonic() + timeout
    windows: list[tuple[int, str]] = []
    while time.monotonic() < deadline:
        windows = []
        for hwnd, title in visible_windows_for_pid(pid):
            try:
                rect_for(hwnd)
            except Exception:
                continue
            windows.append((hwnd, title))
        if len(windows) >= count:
            return windows
        time.sleep(0.12)
    return windows


def clamp_bbox(left: int, top: int, right: int, bottom: int) -> tuple[int, int, int, int]:
    screen_w = user32.GetSystemMetrics(78) or user32.GetSystemMetrics(0)
    screen_h = user32.GetSystemMetrics(79) or user32.GetSystemMetrics(1)
    origin_x = user32.GetSystemMetrics(76)
    origin_y = user32.GetSystemMetrics(77)
    return (
        max(origin_x, left),
        max(origin_y, top),
        min(origin_x + screen_w, right),
        min(origin_y + screen_h, bottom),
    )


def capture_bgra(bbox: tuple[int, int, int, int]) -> tuple[bytes, int, int]:
    left, top, right, bottom = bbox
    width = max(1, right - left)
    height = max(1, bottom - top)
    screen_dc = user32.GetDC(None)
    if not screen_dc:
        raise RuntimeError("GetDC failed")
    mem_dc = gdi32.CreateCompatibleDC(screen_dc)
    bitmap = gdi32.CreateCompatibleBitmap(screen_dc, width, height)
    if not mem_dc or not bitmap:
        if bitmap:
            gdi32.DeleteObject(bitmap)
        if mem_dc:
            gdi32.DeleteDC(mem_dc)
        user32.ReleaseDC(None, screen_dc)
        raise RuntimeError("CreateCompatibleDC/CreateCompatibleBitmap failed")
    old_obj = gdi32.SelectObject(mem_dc, bitmap)
    try:
        if not gdi32.BitBlt(mem_dc, 0, 0, width, height, screen_dc, left, top, SRCCOPY):
            raise RuntimeError("BitBlt failed")
        info = BITMAPINFO()
        info.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        info.bmiHeader.biWidth = width
        info.bmiHeader.biHeight = -height
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = BI_RGB
        info.bmiHeader.biSizeImage = width * height * 4
        buffer = (ctypes.c_ubyte * (width * height * 4))()
        lines = gdi32.GetDIBits(mem_dc, bitmap, 0, height, buffer, ctypes.byref(info), DIB_RGB_COLORS)
        if lines != height:
            raise RuntimeError(f"GetDIBits copied {lines}/{height} lines")
        return bytes(buffer), width, height
    finally:
        if old_obj:
            gdi32.SelectObject(mem_dc, old_obj)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(mem_dc)
        user32.ReleaseDC(None, screen_dc)


def write_bmp(path: Path, bgra: bytes, width: int, height: int) -> None:
    row_size = width * 4
    bottom_up = bytearray()
    for y in range(height - 1, -1, -1):
        start = y * row_size
        bottom_up.extend(bgra[start : start + row_size])
    file_header_size = 14
    info_header_size = 40
    pixel_offset = file_header_size + info_header_size
    file_size = pixel_offset + len(bottom_up)
    header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, pixel_offset)
    info = struct.pack(
        "<IiiHHIIiiII",
        info_header_size,
        width,
        height,
        1,
        32,
        BI_RGB,
        len(bottom_up),
        0,
        0,
        0,
        0,
    )
    path.write_bytes(header + info + bytes(bottom_up))


def grab_rect(name: str, rect: tuple[int, int, int, int], pad: int = 0) -> tuple[Path, bytes, int, int, tuple[int, int, int, int]]:
    left, top, right, bottom = rect
    bbox = clamp_bbox(left - pad, top - pad, right + pad, bottom + pad)
    if bbox[2] <= bbox[0] or bbox[3] <= bbox[1]:
        raise RuntimeError(f"invalid capture bbox: {bbox}")
    pixels, width, height = capture_bgra(bbox)
    path = OUT_DIR / f"{name}.bmp"
    write_bmp(path, pixels, width, height)
    return path, pixels, width, height, bbox


def expansion_black_stats(
    pixels: bytes,
    width: int,
    height: int,
    capture_bbox: tuple[int, int, int, int],
    old_rect: tuple[int, int, int, int],
    new_rect: tuple[int, int, int, int],
    threshold: int = 14,
) -> dict[str, float | int]:
    cap_left, cap_top, _cap_right, _cap_bottom = capture_bbox
    old_left, old_top, old_right, old_bottom = old_rect
    new_left, new_top, new_right, new_bottom = new_rect
    total = 0
    near_black = 0
    pure_black = 0
    for y in range(max(new_top, cap_top), min(new_bottom, cap_top + height)):
        for x in range(max(new_left, cap_left), min(new_right, cap_left + width)):
            in_old = old_left <= x < old_right and old_top <= y < old_bottom
            if in_old:
                continue
            # Ignore the 1px outermost edge where anti-aliased rounded regions
            # and the desktop background can legitimately appear.
            if x <= new_left or y <= new_top or x >= new_right - 1 or y >= new_bottom - 1:
                continue
            ix = x - cap_left
            iy = y - cap_top
            offset = (iy * width + ix) * 4
            b = pixels[offset]
            g = pixels[offset + 1]
            r = pixels[offset + 2]
            total += 1
            if r == 0 and g == 0 and b == 0:
                pure_black += 1
            if r <= threshold and g <= threshold and b <= threshold:
                near_black += 1
    near_ratio = near_black / total if total else 0.0
    pure_ratio = pure_black / total if total else 0.0
    return {
        "total": total,
        "near_black": near_black,
        "pure_black": pure_black,
        "near_black_ratio": near_ratio,
        "pure_black_ratio": pure_ratio,
    }


def move_to(x: int, y: int, delay: float = 0.04) -> None:
    user32.SetCursorPos(int(x), int(y))
    time.sleep(delay)


def click(x: int, y: int) -> None:
    move_to(x, y)
    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    time.sleep(0.06)
    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    time.sleep(0.18)


def drag_hold(
    pid: int,
    shadow_mode: str,
    hwnd: int,
    initial_rect: tuple[int, int, int, int],
    label: str,
    x1: int,
    y1: int,
    x2: int,
    y2: int,
    steps: int = 16,
) -> tuple[Path | None, dict[str, float | int], tuple[int, int, int, int]]:
    move_to(x1, y1)
    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    best_path: Path | None = None
    best_stats: dict[str, float | int] = {}
    best_rect = initial_rect
    best_score = -1.0
    for i in range(1, steps + 1):
        if shadow_mode == "hide":
            hide_shadow_windows(pid)
        x = int(x1 + (x2 - x1) * i / steps)
        y = int(y1 + (y2 - y1) * i / steps)
        user32.SetCursorPos(x, y)
        time.sleep(0.006)
        if shadow_mode == "hide":
            hide_shadow_windows(pid)
        rect = rect_for(hwnd)
        path, pixels, width, height, bbox = grab_rect(f"{label}_step_{i:02d}", rect, pad=0)
        stats = expansion_black_stats(pixels, width, height, bbox, initial_rect, rect)
        score = float(stats.get("near_black_ratio", 0.0)) * max(1, int(stats.get("total", 0)))
        if score > best_score and int(stats.get("total", 0)) > 0:
            best_score = score
            best_path = path
            best_stats = stats
            best_rect = rect
    return best_path, best_stats, best_rect


def native_size_hold(
    pid: int,
    shadow_mode: str,
    hwnd: int,
    initial_rect: tuple[int, int, int, int],
    label: str,
    x1: int,
    y1: int,
    x2: int,
    y2: int,
    steps: int = 16,
) -> tuple[Path | None, dict[str, float | int], tuple[int, int, int, int]]:
    move_to(x1, y1)
    user32.PostMessageW(wintypes.HWND(hwnd), WM_NCLBUTTONDOWN, HTBOTTOMRIGHT, lparam_from_point(x1, y1))
    time.sleep(0.05)
    best_path: Path | None = None
    best_stats: dict[str, float | int] = {}
    best_rect = initial_rect
    best_score = -1.0
    for i in range(1, steps + 1):
        if shadow_mode == "hide":
            hide_shadow_windows(pid)
        x = int(x1 + (x2 - x1) * i / steps)
        y = int(y1 + (y2 - y1) * i / steps)
        user32.SetCursorPos(x, y)
        time.sleep(0.018)
        if shadow_mode == "hide":
            hide_shadow_windows(pid)
        rect = rect_for(hwnd)
        path, pixels, width, height, bbox = grab_rect(f"{label}_native_step_{i:02d}", rect, pad=0)
        stats = expansion_black_stats(pixels, width, height, bbox, initial_rect, rect)
        score = float(stats.get("near_black_ratio", 0.0)) * max(1, int(stats.get("total", 0)))
        if score > best_score and int(stats.get("total", 0)) > 0:
            best_score = score
            best_path = path
            best_stats = stats
            best_rect = rect
    release_mouse()
    return best_path, best_stats, best_rect


def release_mouse() -> None:
    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    time.sleep(0.35)


def signed_word(value: int) -> int:
    value = int(value) & 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def lparam_from_point(x: int, y: int) -> int:
    return (signed_word(y) & 0xFFFF) << 16 | (signed_word(x) & 0xFFFF)


def hit_test(hwnd: int, x: int, y: int) -> int:
    return int(user32.SendMessageW(wintypes.HWND(hwnd), WM_NCHITTEST, 0, lparam_from_point(x, y)))


def find_resize_start(hwnd: int, rect: tuple[int, int, int, int]) -> tuple[int, int, int]:
    left, top, right, bottom = rect
    for inset in range(1, 24):
        x = right - inset
        y = bottom - inset
        hit = hit_test(hwnd, x, y)
        if hit == HTBOTTOMRIGHT:
            return x, y, hit
    for inset in range(1, 24):
        x = right - inset
        y = top + max(24, (bottom - top) // 2)
        hit = hit_test(hwnd, x, y)
        if hit == HTRIGHT:
            return x, y, hit
    for inset in range(1, 24):
        x = left + max(24, (right - left) // 2)
        y = bottom - inset
        hit = hit_test(hwnd, x, y)
        if hit == HTBOTTOM:
            return x, y, hit
    return right - 3, bottom - 3, hit_test(hwnd, right - 3, bottom - 3)


def close_by_click(hwnd: int) -> None:
    left, top, right, _bottom = rect_for(hwnd)
    user32.SetForegroundWindow(wintypes.HWND(hwnd))
    time.sleep(0.2)
    click(right - 17, top + 21)


def run_probe(args: argparse.Namespace) -> int:
    if args.clean and OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["QROUNDEDFRAME_SMOKE_CLOSE_MS"] = "600000"
    if args.shadow_mode == "disable":
        env["QROUNDEDFRAME_DISABLE_NATIVE_SHADOW"] = "1"
    proc = subprocess.Popen([sys.executable, "run.py"], cwd=ROOT, env=env)
    paths: list[Path] = []
    stats: dict[str, float | int] = {}
    hidden_count = 0
    try:
        windows = wait_for_windows(proc.pid, 1)
        if not windows:
            print("no windows")
            return 2
        main_hwnd = windows[0][0]
        user32.SetForegroundWindow(wintypes.HWND(main_hwnd))
        time.sleep(args.initial_delay)
        if args.shadow_mode == "hide":
            hidden_count += hide_shadow_windows(proc.pid)
        initial_rect = rect_for(main_hwnd)
        path, _pixels, _w, _h, _bbox = grab_rect(f"{args.label}_01_initial", initial_rect, pad=args.pad)
        paths.append(path)

        left, top, right, bottom = initial_rect
        start_x, start_y, start_hit = find_resize_start(main_hwnd, initial_rect)
        best_step_path, best_step_stats, best_step_rect = drag_hold(
            proc.pid,
            args.shadow_mode,
            main_hwnd,
            initial_rect,
            f"{args.label}_02_during_resize",
            start_x,
            start_y,
            right + args.resize_dx,
            bottom + args.resize_dy,
            args.steps,
        )
        if rect_for(main_hwnd) == initial_rect:
            release_mouse()
            best_step_path, best_step_stats, best_step_rect = native_size_hold(
                proc.pid,
                args.shadow_mode,
                main_hwnd,
                initial_rect,
                f"{args.label}_02_during_resize",
                start_x,
                start_y,
                right + args.resize_dx,
                bottom + args.resize_dy,
                args.steps,
            )
        if args.shadow_mode == "hide":
            hidden_count += hide_shadow_windows(proc.pid)
        during_rect = rect_for(main_hwnd)
        path, pixels, width, height, bbox = grab_rect(f"{args.label}_02_during_resize", during_rect, pad=args.pad)
        paths.append(path)
        stats = expansion_black_stats(pixels, width, height, bbox, initial_rect, during_rect, args.black_threshold)
        if best_step_path is not None:
            paths.append(best_step_path)
            if float(best_step_stats.get("near_black_ratio", 0.0)) > float(stats.get("near_black_ratio", 0.0)):
                stats = best_step_stats
                during_rect = best_step_rect
        release_mouse()
        if args.shadow_mode == "hide":
            hidden_count += hide_shadow_windows(proc.pid)
        after_rect = rect_for(main_hwnd)
        path, _pixels, _w, _h, _bbox = grab_rect(f"{args.label}_03_after_resize", after_rect, pad=args.pad)
        paths.append(path)

        close_by_click(main_hwnd)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            user32.PostMessageW(wintypes.HWND(main_hwnd), WM_SYSCOMMAND, SC_CLOSE, 0)
            proc.wait(timeout=3)
    finally:
        release_mouse()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)

    print(f"shadow_mode={args.shadow_mode}")
    print(f"hidden_shadow_windows={hidden_count}")
    print(f"exit_code={proc.returncode}")
    print(f"initial_rect={initial_rect[0]},{initial_rect[1]},{initial_rect[2]},{initial_rect[3]}")
    print(f"during_rect={during_rect[0]},{during_rect[1]},{during_rect[2]},{during_rect[3]}")
    print(f"after_rect={after_rect[0]},{after_rect[1]},{after_rect[2]},{after_rect[3]}")
    print(f"resize_start={start_x},{start_y} hit={start_hit}")
    print(f"expansion_size={max(0, during_rect[2] - initial_rect[2])}x{max(0, during_rect[3] - initial_rect[3])}")
    for key in ("total", "near_black", "pure_black", "near_black_ratio", "pure_black_ratio"):
        value = stats.get(key, 0)
        if isinstance(value, float):
            print(f"{key}={value:.6f}")
        else:
            print(f"{key}={value}")
    for path in paths:
        print(path)
    return 0 if proc.returncode in (0, None) else int(proc.returncode)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Win32 visual probe for live-resize black fill.")
    parser.add_argument("--shadow-mode", choices=("on", "hide", "disable"), default="on")
    parser.add_argument("--label", default="", help="Screenshot filename prefix.")
    parser.add_argument("--resize-dx", type=int, default=96)
    parser.add_argument("--resize-dy", type=int, default=58)
    parser.add_argument("--steps", type=int, default=18)
    parser.add_argument("--pad", type=int, default=0)
    parser.add_argument("--black-threshold", type=int, default=14)
    parser.add_argument("--initial-delay", type=float, default=0.8)
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()
    if not args.label:
        args.label = args.shadow_mode
    return args


def main() -> int:
    return run_probe(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
