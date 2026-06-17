from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


APP_NAME = "QRoundedFrame"
DEFAULT_QT_PREFIX = Path(r"Z:\Qt\6.11.1\msvc2022_64")
QT_DLLS = [
    "Qt6Core.dll",
    "Qt6Gui.dll",
    "Qt6LabsPlatform.dll",
    "Qt6Network.dll",
    "Qt6OpenGL.dll",
    "Qt6Qml.dll",
    "Qt6QmlMeta.dll",
    "Qt6QmlModels.dll",
    "Qt6QmlWorkerScript.dll",
    "Qt6Quick.dll",
    "Qt6QuickControls2.dll",
    "Qt6QuickControls2Basic.dll",
    "Qt6QuickControls2BasicStyleImpl.dll",
    "Qt6QuickControls2Impl.dll",
    "Qt6QuickLayouts.dll",
    "Qt6QuickTemplates2.dll",
    "Qt6Sql.dll",
    "Qt6Svg.dll",
    "Qt6Widgets.dll",
]
QT_PLUGIN_DIRS = [
    "platforms",
    "imageformats",
    "iconengines",
    "styles",
    "tls",
]
QT_QML_MODULE_DIRS = [
    "QtCore",
    "QtQml",
    "QtQuick",
    "QtQuick.2",
    "QtQuick/Controls",
    "QtQuick/Controls/Basic",
    "QtQuick/Controls/Basic/impl",
    "QtQuick/Controls/impl",
    "QtQuick/Layouts",
    "QtQuick/Templates",
    "QtQuick/Window",
    "Qt/labs/platform",
]


LINUX_RUNTIME_APP_FILES = [
    "__init__.py",
    "memory_snapshot.py",
    "window_policy.py",
    "windows_compat.py",
]


def run(cmd: list[str], cwd: Path) -> None:
    print(">", " ".join(cmd))
    subprocess.run(cmd, cwd=str(cwd), check=True)


def remove_tree(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)


def copy_tree(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(src)
    remove_tree(dst)
    shutil.copytree(src, dst)


def copy_file(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def qt_prefix() -> Path:
    value = os.environ.get("FRAMELESS_QT_PREFIX", "").strip()
    return Path(value) if value else DEFAULT_QT_PREFIX


def copy_qt_runtime(qt: Path, release_dir: Path) -> None:
    qt_bin = qt / "bin"
    qt_plugins = qt / "plugins"
    qt_qml = qt / "qml"
    if not (qt_bin / "Qt6Core.dll").exists():
        raise FileNotFoundError(f"Qt runtime not found: {qt_bin}")

    for dll in QT_DLLS:
        copy_file(qt_bin / dll, release_dir / dll)

    for name in QT_PLUGIN_DIRS:
        source = qt_plugins / name
        if source.exists():
            copy_tree(source, release_dir / name)

    sqlite_driver = qt_plugins / "sqldrivers" / "qsqlite.dll"
    if sqlite_driver.exists():
        copy_file(sqlite_driver, release_dir / "sqldrivers" / "qsqlite.dll")

    for name in QT_QML_MODULE_DIRS:
        source = qt_qml / name
        if source.exists():
            copy_tree(source, release_dir / "qml" / name)


def build_launcher(root: Path, output: Path) -> None:
    source = root / "app" / "cpp" / "launcher" / "launcher.cpp"
    resource = root / "app" / "cpp" / "launcher" / "launcher.rc"
    if not source.exists():
        raise FileNotFoundError(source)
    if not resource.exists():
        raise FileNotFoundError(resource)
    output.parent.mkdir(parents=True, exist_ok=True)
    vcvars = Path(os.environ.get(
        "FRAMELESS_VCVARS",
        r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
    ))
    if not vcvars.exists():
        raise FileNotFoundError(f"Visual Studio vcvars64.bat not found: {vcvars}")
    with tempfile.NamedTemporaryFile("w", suffix=".bat", delete=False, encoding="utf-8", newline="\r\n") as file:
        batch_path = Path(file.name)
        res_path = output.with_suffix(".res")
        obj_path = output.with_suffix(".obj")
        file.write("@echo off\n")
        file.write(f'call "{vcvars}" >nul\n')
        file.write(f'rc /nologo /fo "{res_path}" "{resource}"\n')
        file.write(
            f'cl /nologo /std:c++17 /O2 /EHsc /DUNICODE /D_UNICODE '
            f'/Fo:"{obj_path}" /Fe:"{output}" "{source}" "{res_path}" shell32.lib user32.lib /link /SUBSYSTEM:WINDOWS\n'
        )
    try:
        run(["cmd", "/c", str(batch_path)], root)
    finally:
        try:
            batch_path.unlink()
        except FileNotFoundError:
            pass
        try:
            output.with_suffix(".res").unlink()
        except FileNotFoundError:
            pass
        try:
            output.with_suffix(".obj").unlink()
        except FileNotFoundError:
            pass


def prune_release(release_dir: Path) -> None:
    for pattern in ("*.lib", "*.exp", "*.pdb", "*.pyc", "*.pyo"):
        for path in release_dir.rglob(pattern):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
    for path in release_dir.rglob("__pycache__"):
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)


def write_linux_launcher(release_dir: Path, app_name: str) -> None:
    launcher = release_dir / "run.sh"
    launcher.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        'export QROUNDEDFRAME_ROOT="${QROUNDEDFRAME_ROOT:-$ROOT}"\n'
        'exec "$ROOT/bin/' + app_name + '" "$@"\n',
        encoding="utf-8",
        newline="\n",
    )
    launcher.chmod(0o755)


def write_linux_desktop_file(release_dir: Path, app_name: str) -> None:
    desktop = release_dir / f"{app_name}.desktop"
    desktop.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={app_name}\n"
        f"Exec={release_dir / 'run.sh'}\n"
        f"Icon={release_dir / 'resources' / 'app_icon.ico'}\n"
        "Terminal=false\n"
        "Categories=Utility;\n",
        encoding="utf-8",
        newline="\n",
    )


def copy_linux_runtime_app(root: Path, release_dir: Path) -> None:
    app_dst = release_dir / "app"
    app_dst.mkdir(parents=True, exist_ok=True)
    for name in LINUX_RUNTIME_APP_FILES:
        source = root / "app" / name
        if source.exists():
            copy_file(source, app_dst / name)
    copy_tree(root / "app" / "workers", app_dst / "workers")
    copy_tree(root / "app" / "prebuilt", app_dst / "prebuilt")


def check_linux_prebuilt(root: Path) -> None:
    for variant in ("system", "custom"):
        base = root / "app" / "prebuilt" / f"linux-x64-qt6.11-{variant}" / "qml" / "FramelessNative"
        for name in ("qmldir", "FramelessNative.qmltypes", "libFramelessNative.so", "libFramelessNativeplugin.so"):
            if not (base / name).exists():
                raise FileNotFoundError(base / name)


def package_linux(root: Path, app_name: str, dist_dir: Path, clean: bool) -> Path:
    if clean:
        remove_tree(dist_dir / app_name)

    run([sys.executable, "scripts/check_text_encoding.py"], root)
    run(["bash", str(root / "app" / "cpp" / "frameless_native" / "build_linux.sh")], root)
    check_linux_prebuilt(root)
    run(["bash", str(root / "app" / "cpp" / "ui_runtime" / "build_linux.sh")], root)

    release_dir = dist_dir / app_name
    bin_dir = release_dir / "bin"
    release_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)

    copy_file(root / "build" / "cpp_ui" / "linux" / "bin" / "QRoundedFrame", bin_dir / app_name)
    copy_tree(root / "qml", release_dir / "qml")
    copy_tree(root / "resources" / "icons", release_dir / "resources" / "icons")
    copy_tree(root / "resources" / "images", release_dir / "resources" / "images")
    copy_file(root / "resources" / "app_icon.ico", release_dir / "resources" / "app_icon.ico")
    copy_linux_runtime_app(root, release_dir)
    write_linux_launcher(release_dir, app_name)
    write_linux_desktop_file(release_dir, app_name)
    prune_release(release_dir)
    return release_dir


def package_windows(root: Path, app_name: str, dist_dir: Path, clean: bool) -> Path:
    if clean:
        remove_tree(dist_dir / app_name)

    run([sys.executable, "scripts/check_text_encoding.py"], root)
    run([sys.executable, "scripts/check_native_window_integrity.py", "--require-prebuilt", "--summary"], root)
    run(["cmd", "/c", str(root / "app" / "cpp" / "ui_runtime" / "build_windows.bat")], root)

    release_dir = dist_dir / app_name
    runtime_dir = release_dir / "runtime"
    release_dir.mkdir(parents=True, exist_ok=True)
    runtime_dir.mkdir(parents=True, exist_ok=True)

    exe = root / "build" / "cpp_ui" / "bin" / "QRoundedFrame.exe"
    copy_file(exe, runtime_dir / f"{app_name}.exe")
    build_launcher(root, release_dir / f"{app_name}.exe")
    if (root / "resources" / "app_icon.ico").exists():
        copy_file(root / "resources" / "app_icon.ico", runtime_dir / "resources" / "app_icon.ico")

    copy_tree(root / "qml", runtime_dir / "qml")
    copy_tree(root / "resources" / "icons", runtime_dir / "resources" / "icons")
    copy_tree(root / "resources" / "images", runtime_dir / "resources" / "images")
    copy_tree(root / "app" / "prebuilt", runtime_dir / "app" / "prebuilt")
    copy_qt_runtime(qt_prefix(), runtime_dir)
    prune_release(runtime_dir)
    return release_dir


def package(root: Path, app_name: str, dist_dir: Path, clean: bool, target: str) -> Path:
    if target == "linux":
        return package_linux(root, app_name, dist_dir, clean)
    if target == "windows":
        return package_windows(root, app_name, dist_dir, clean)
    raise ValueError(f"Unsupported package target: {target}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Package the C++ Qt Quick UI runtime.")
    parser.add_argument("--name", default=os.environ.get("APP_NAME", APP_NAME))
    parser.add_argument("--dist", default=os.environ.get("DIST_DIR", "dist"))
    parser.add_argument(
        "--target",
        choices=("windows", "linux"),
        default=os.environ.get("PACKAGE_TARGET") or ("windows" if platform.system() == "Windows" else "linux"),
    )
    parser.add_argument("--no-clean", action="store_true", help="Do not delete previous package output first.")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    release_dir = package(
        root=root,
        app_name=args.name,
        dist_dir=(root / args.dist).resolve(),
        clean=not args.no_clean,
        target=args.target,
    )
    print()
    if args.target == "windows":
        print(f"Packaged: {release_dir / (args.name + '.exe')}")
    else:
        print(f"Packaged: {release_dir / 'run.sh'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
