from __future__ import annotations

import argparse
import os
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


def package(root: Path, app_name: str, dist_dir: Path, clean: bool) -> Path:
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Package the C++ Qt Quick UI runtime.")
    parser.add_argument("--name", default=os.environ.get("APP_NAME", APP_NAME))
    parser.add_argument("--dist", default=os.environ.get("DIST_DIR", "dist"))
    parser.add_argument("--no-clean", action="store_true", help="Do not delete previous package output first.")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    release_dir = package(
        root=root,
        app_name=args.name,
        dist_dir=(root / args.dist).resolve(),
        clean=not args.no_clean,
    )
    print()
    print(f"Packaged: {release_dir / (args.name + '.exe')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
