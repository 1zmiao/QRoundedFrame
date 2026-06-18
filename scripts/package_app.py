from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile
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

LINUX_QT_LIBS = [
    "libQt6Core.so.6",
    "libQt6Gui.so.6",
    "libQt6LabsPlatform.so.6",
    "libQt6Network.so.6",
    "libQt6OpenGL.so.6",
    "libQt6Qml.so.6",
    "libQt6QmlMeta.so.6",
    "libQt6QmlModels.so.6",
    "libQt6QmlWorkerScript.so.6",
    "libQt6Quick.so.6",
    "libQt6QuickControls2.so.6",
    "libQt6QuickControls2Basic.so.6",
    "libQt6QuickControls2BasicStyleImpl.so.6",
    "libQt6QuickControls2Impl.so.6",
    "libQt6QuickLayouts.so.6",
    "libQt6QuickTemplates2.so.6",
    "libQt6Sql.so.6",
    "libQt6Svg.so.6",
    "libQt6Widgets.so.6",
    "libQt6Concurrent.so.6",
    "libQt6DBus.so.6",
]
LINUX_QT_PLUGIN_DIRS = [
    "platforms",
    "imageformats",
    "iconengines",
    "styles",
    "tls",
    "platforminputcontexts",
    "xcbglintegrations",
]
LINUX_QT_QML_MODULE_DIRS = [
    "QtCore",
    "QtQml",
    "QtQuick",
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


def archive_platform_suffix(target: str) -> str:
    machine = platform.machine().lower()
    arch = "x64" if machine in {"amd64", "x86_64"} else machine.replace(" ", "-") or "unknown"
    return f"{target}-{arch}"


def make_zip_archive(release_dir: Path, target: str) -> Path:
    archive_path = release_dir.parent / f"{release_dir.name}-{archive_platform_suffix(target)}.zip"
    if archive_path.exists():
        archive_path.unlink()
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(release_dir.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(release_dir.parent).as_posix())
    return archive_path


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


def find_linux_qt_dirs() -> tuple[Path, Path, Path]:
    qt_prefix_env = os.environ.get("FRAMELESS_QT_PREFIX", "").strip()
    if qt_prefix_env:
        prefix = Path(qt_prefix_env)
        lib_dir = prefix / "lib"
        plugins_dir = prefix / "plugins"
        qml_dir = prefix / "qml"
        if lib_dir.exists() and plugins_dir.exists():
            return lib_dir, plugins_dir, qml_dir

    try:
        result = subprocess.run(
            ["qtpaths6", "--qt-query", "QT_INSTALL_LIBS"],
            capture_output=True, text=True, check=True,
        )
        lib_dir = Path(result.stdout.strip())
        result = subprocess.run(
            ["qtpaths6", "--qt-query", "QT_INSTALL_PLUGINS"],
            capture_output=True, text=True, check=True,
        )
        plugins_dir = Path(result.stdout.strip())
        result = subprocess.run(
            ["qtpaths6", "--qt-query", "QT_INSTALL_QML"],
            capture_output=True, text=True, check=True,
        )
        qml_dir = Path(result.stdout.strip())
        return lib_dir, plugins_dir, qml_dir
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    candidate = Path("/usr/lib/x86_64-linux-gnu")
    if (candidate / "libQt6Core.so.6").exists():
        return candidate, candidate / "qt6" / "plugins", candidate / "qt6" / "qml"
    raise FileNotFoundError(
        "Qt 6 runtime not found. Set FRAMELESS_QT_PREFIX or install Qt 6 development packages."
    )


def _prune_unnecessary_qt(release_dir: Path) -> None:
    unnecessary_qml_subdirs = [
        "QtQuick/VirtualKeyboard",
        "QtQuick/Particles",
        "QtQuick/Shapes",
        "QtQuick/Effects",
        "QtQuick/VectorImage",
        "QtQuick/tooling",
        "QtQuick/LocalStorage",
        "QtQuick/Dialogs",
        "QtQuick/NativeStyle",
    ]
    for name in unnecessary_qml_subdirs:
        path = release_dir / "qml" / name
        if path.exists():
            shutil.rmtree(path)

    unnecessary_qml_styles = [
        "QtQuick/Controls/designer",
        "QtQuick/Controls/Fusion",
        "QtQuick/Controls/Imagine",
        "QtQuick/Controls/Material",
        "QtQuick/Controls/Universal",
    ]
    for name in unnecessary_qml_styles:
        path = release_dir / "qml" / name
        if path.exists():
            shutil.rmtree(path)

    img_dir = release_dir / "plugins" / "imageformats"
    if img_dir.exists():
        for f in list(img_dir.iterdir()):
            if f.name.startswith("kimg_"):
                f.unlink()


def copy_linux_qt_runtime(release_dir: Path) -> None:
    lib_dir, plugins_dir, qml_dir = find_linux_qt_dirs()

    lib_dst = release_dir / "lib"
    lib_dst.mkdir(parents=True, exist_ok=True)
    for so_name in LINUX_QT_LIBS:
        source = lib_dir / so_name
        if source.exists():
            shutil.copy2(source, lib_dst / so_name, follow_symlinks=True)
        else:
            print(f"  [warn] Qt library not found: {source}")

    plugins_dst = release_dir / "plugins"
    for name in LINUX_QT_PLUGIN_DIRS:
        source = plugins_dir / name
        if source.exists():
            copy_tree(source, plugins_dst / name)

    sqlite_driver = plugins_dir / "sqldrivers" / "libqsqlite.so"
    if sqlite_driver.exists():
        copy_file(sqlite_driver, plugins_dst / "sqldrivers" / "libqsqlite.so")

    for name in LINUX_QT_QML_MODULE_DIRS:
        source = qml_dir / name
        if source.exists():
            copy_tree(source, release_dir / "qml" / name)

    _prune_unnecessary_qt(release_dir)


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
        'export QROUNDEDFRAME_ROOT="$ROOT"\n'
        'export LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n'
        'export QT_PLUGIN_PATH="$ROOT/plugins"\n'
        'export QML2_IMPORT_PATH="$ROOT/qml"\n'
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
    copy_linux_qt_runtime(release_dir)
    for stale in ("runtime", "QRoundedFrame.exe"):
        p = release_dir / stale
        if p.exists():
            remove_tree(p) if p.is_dir() else p.unlink()
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
    archive_path = make_zip_archive(release_dir, args.target)
    print()
    if args.target == "windows":
        print(f"Packaged: {release_dir / (args.name + '.exe')}")
    else:
        print(f"Packaged: {release_dir / 'run.sh'}")
    print(f"Archive:  {archive_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
