from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_QT_PREFIX = Path(r"Z:\Qt\6.11.1\msvc2022_64")


def _is_windows() -> bool:
    return os.name == "nt"


def _linux_desktop_text(env: dict[str, str]) -> str:
    return ";".join(
        env.get(name, "")
        for name in ("XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION")
    ).lower()


def _kde_screen_scale() -> float | None:
    path = Path.home() / ".config" / "kdeglobals"
    if not path.exists():
        return None
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None

    in_kscreen = False
    screen_scale_factors = ""
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_kscreen = line[1:-1] == "KScreen"
            continue
        if not in_kscreen or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "ScaleFactor":
            try:
                scale = float(value.strip())
            except ValueError:
                scale = 0.0
            if scale > 0:
                return max(1.0, scale)
        elif key == "ScreenScaleFactors":
            screen_scale_factors = value.strip()

    for part in screen_scale_factors.split(";"):
        if "=" not in part:
            continue
        try:
            value = float(part.rsplit("=", 1)[1])
        except ValueError:
            continue
        if value > 0:
            return max(1.0, value)
    return None


def _qt_screen_scale_is_stale(env: dict[str, str], kde_scale: float) -> bool:
    raw = env.get("QT_SCREEN_SCALE_FACTORS", "").strip()
    if not raw:
        return False
    values: list[float] = []
    for part in raw.split(";"):
        if not part:
            continue
        text = part.rsplit("=", 1)[-1].strip()
        try:
            values.append(float(text))
        except ValueError:
            return False
    return bool(values) and any(abs(value - kde_scale) > 0.001 for value in values)


def _normalize_linux_qt_scale_env(env: dict[str, str]) -> None:
    if _is_windows():
        return
    desktop = _linux_desktop_text(env)
    if "kde" not in desktop and "plasma" not in desktop:
        return
    kde_scale = _kde_screen_scale()
    if kde_scale is None:
        return
    if _qt_screen_scale_is_stale(env, kde_scale):
        env.pop("QT_SCREEN_SCALE_FACTORS", None)


def _exe_path() -> Path:
    if _is_windows():
        return ROOT / "build" / "cpp_ui" / "bin" / "QRoundedFrame.exe"
    return ROOT / "build" / "cpp_ui" / "linux" / "bin" / "QRoundedFrame"


def _build_script() -> Path:
    if _is_windows():
        return ROOT / "app" / "cpp" / "ui_runtime" / "build_windows.bat"
    return ROOT / "app" / "cpp" / "ui_runtime" / "build_linux.sh"


def _native_plugin_dir() -> Path:
    tag = "win-x64-qt6.11-custom" if _is_windows() else "linux-x64-qt6.11-custom"
    return ROOT / "app" / "prebuilt" / tag / "qml" / "FramelessNative"


def _qt_prefix() -> Path:
    value = os.environ.get("FRAMELESS_QT_PREFIX", "").strip()
    return Path(value) if value else DEFAULT_QT_PREFIX


def _build_if_needed() -> int:
    exe = _exe_path()
    if exe.exists():
        return 0
    build_script = _build_script()
    if not build_script.exists():
        print(f"C++ UI build script not found: {build_script}", file=sys.stderr)
        return 1
    if _is_windows():
        completed = subprocess.run(["cmd", "/c", str(build_script)], cwd=ROOT)
    else:
        completed = subprocess.run(["bash", str(build_script)], cwd=ROOT)
    return int(completed.returncode)


def launch_cpp_ui(argv: list[str] | None = None) -> int:
    code = _build_if_needed()
    if code != 0:
        return code

    env = os.environ.copy()
    _normalize_linux_qt_scale_env(env)
    native_plugin_dir = _native_plugin_dir()
    if _is_windows():
        qt_prefix = _qt_prefix()
        qt_bin = qt_prefix / "bin"
        if not (qt_bin / "Qt6Core.dll").exists():
            print(f"Qt runtime not found: {qt_bin}", file=sys.stderr)
            return 1

        path_parts = [str(qt_bin)]
        if native_plugin_dir.exists():
            path_parts.append(str(native_plugin_dir))
        path_parts.append(env.get("PATH", ""))
        env["PATH"] = os.pathsep.join(path_parts)
    env["QROUNDEDFRAME_ROOT"] = str(ROOT)

    args = [str(_exe_path())]
    if argv:
        args.extend(argv)
    if os.environ.get("QROUNDEDFRAME_CPP_WAIT", "").strip().lower() in {"1", "true", "yes", "on"}:
        completed = subprocess.run(args, cwd=ROOT, env=env)
        return int(completed.returncode)

    subprocess.Popen(args, cwd=ROOT, env=env)
    return 0
