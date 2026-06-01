from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SRC = ROOT / "app" / "cpp" / "frameless_native" / "src"
PREBUILT = ROOT / "app" / "native" / "prebuilt"
TAG = "win32-x64-py310-qt6.11"

ERRORS: list[str] = []
WARNINGS: list[str] = []


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT)).replace("\\", "/")
    except Exception:
        return str(path)


def fail(message: str) -> None:
    ERRORS.append(message)


def warn(message: str) -> None:
    WARNINGS.append(message)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8-sig")


def check_native_agent() -> None:
    path = NATIVE_SRC / "native_window_agent.cpp"
    header = NATIVE_SRC / "native_window_agent.h"
    text = read_text(path) + "\n" + read_text(header)
    forbidden = {
        "QEvent::Expose": "Do not reapply DWM attributes on Expose; it can cause Qt Quick repaint storms.",
        "scheduleApplyWindowAttributes": "Do not queue repeated DWM/style reapplication.",
        "scheduleApplyRoundedRegion": "Do not update HWND regions from a live resize debounce; it causes Win10 resize jitter.",
        "QAbstractNativeEventFilter": "NativeWindowAgent must not install a global message hook for resize-region fixes.",
        "SetWindowLongPtrW": "Do not rewrite the main HWND style in NativeWindowAgent; QWindowKit owns it.",
        "SWP_FRAMECHANGED": "Do not force main HWND frame changes from NativeWindowAgent.",
        "WS_POPUP": "Do not force WS_POPUP on the main window; it breaks QWindowKit behavior.",
        "WS_CAPTION": "Do not manually add/remove WS_CAPTION in NativeWindowAgent.",
    }
    for needle, reason in forbidden.items():
        if needle in text:
            fail(f"{rel(path)} contains forbidden pattern {needle!r}. {reason}")

    required = [
        "if (!m_customShadow)",
        "QMargins(0, 0, 0, 0)",
        "DwmExtendFrameIntoClientArea(hwnd, &margins)",
        "DWMNCRP_ENABLED",
        "applyWindowRegion",
        "CreateRoundRectRgn",
        "CreateRectRgn",
        "inwardBias",
        "SetWindowRgn(hwnd, region, TRUE)",
        "SetWindowRgn(hwnd, nullptr",
    ]
    for needle in required:
        if needle not in text:
            fail(f"{rel(path)} is missing required custom-path guard/code: {needle}")
    if "DWMNCRP_DISABLED" in text:
        fail(f"{rel(path)} must keep DWM non-client rendering enabled on the custom path; disabling it exposes classic Win10 frame artifacts.")


def check_external_shadow() -> None:
    path = NATIVE_SRC / "external_shadow_controller.cpp"
    text = read_text(path)
    required = [
        "WS_EX_TRANSPARENT",
        "WS_EX_NOACTIVATE",
        "HTTRANSPARENT",
        "UpdateLayeredWindow",
        "naturalShadowSourceBorder",
        "painter.drawImage",
        "state.opacity * opacityScale",
        "WM_ENTERSIZEMOVE",
        "WM_EXITSIZEMOVE",
        "stackShadowOnly",
        "outerPaddingPx",
        "innerOverlapPx",
        "guardPx",
        "showFlag",
    ]
    for needle in required:
        if needle not in text:
            fail(f"{rel(path)} is missing required external-shadow behavior: {needle}")

    forbidden = {
        "alphaProfile": "Do not synthesize a custom alpha curve; native custom shadow must render the PNG asset.",
        "innerCutoff": "Do not draw shadow into the content area.",
        "qRgba(0, 0, 0, alpha)": "Do not procedurally generate a replacement shadow bitmap.",
        "hideNativeShadow(it.value())": "Do not hide the native shadow during WM_SIZING; it must stay visible while resizing.",
        "if (state.sizing)": "Do not suppress native shadow visibility while sizing.",
    }
    for needle, reason in forbidden.items():
        if needle in text:
            fail(f"{rel(path)} contains forbidden external-shadow pattern {needle!r}. {reason}")

    if "break;    case" in text:
        fail(f"{rel(path)} contains collapsed switch case text: 'break;    case'.")


def check_qml_shadow_path() -> None:
    path = ROOT / "qml" / "window" / "AppWindow.qml"
    text = read_text(path)
    required = [        "property bool nativeExternalShadow: customExternalShadow && Qt.platform.os === \"windows\"",
        "property bool qmlExternalShadow: customExternalShadow && !nativeExternalShadow",
        "| Qt.WindowSystemMenuHint",
        "| Qt.WindowMinimizeButtonHint",
        "| Qt.WindowMaximizeButtonHint",
        "| (root.customExternalShadow ? (Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint) : 0)",
        "targetWindow: (root.qmlExternalShadow && root.customShadowEnabled) ? root : null",
        "externalShadow.destroyNativeShadow(root)",
        "root.scheduleNativeShadowShow()",
        "id: stableNativeShadowSyncTimer",
        "Component.onDestruction: root.cleanupExternalShadow()",
    ]
    for needle in required:
        if needle not in text:
            fail(f"{rel(path)} is missing required shadow split/cleanup code: {needle}")

    forbidden = {
        "property bool _nativeShadowReady": "Do not hide the native shadow behind a delayed readiness gate.",
        "id: nativeShadowReadyTimer": "Do not delay native shadow visibility; only schedule geometry re-syncs.",
        "targetWindow: root.customShadowEnabled ? root : null": "ShadowWindow must be gated through qmlExternalShadow to avoid double shadows.",
    }
    for needle, reason in forbidden.items():
        if needle in text:
            fail(f"{rel(path)} contains forbidden QML shadow pattern {needle!r}. {reason}")

    shadow_path = ROOT / "qml" / "window" / "ShadowWindow.qml"
    shadow_text = read_text(shadow_path)
    for needle in ["smooth: false", "duration: 0", "source: \"../../resources/images/window_shadow.png\"", "property bool nativeControllerGeometry: false", "stackController.stackShadowOnly(root, targetWindow)"]:
        if needle not in shadow_text:
            fail(f"{rel(shadow_path)} is missing required legacy PNG shadow behavior: {needle}")

    if "if (nativeControllerGeometry)" in shadow_text:
        fail(f"{rel(shadow_path)} must not let C++ own QML shadow geometry.")
    if "function onActiveChanged() { root.syncNow(); root.forceStackSync" in shadow_text:
        fail(f"{rel(shadow_path)} must not restack on every activation; it flashes the shadow above the target.")
    for handler in ["onTargetWindowChanged", "onStackControllerChanged"]:
        start = shadow_text.find(handler)
        end = shadow_text.find("\n    on", start + 1)
        block = shadow_text[start:end if end > start else len(shadow_text)] if start >= 0 else ""
        if "registerShadowWindow" in block:
            fail(f"{rel(shadow_path)} must not register the shadow before its QML geometry is applied.")

    child_path = ROOT / "qml" / "window" / "NativeChildWindow.qml"
    child_text = read_text(child_path)
    if "autoShow: false" not in child_text:
        fail(f"{rel(child_path)} must set autoShow: false so child windows do not show before geometry/properties are applied.")

    dialog_path = ROOT / "app" / "bridge" / "dialog_service.py"
    dialog_text = read_text(dialog_path)
    show_index = dialog_text.find("obj.show()")
    restore_index = dialog_text.find("obj.restorePersistedWindowState()")
    if show_index < 0 or restore_index < 0 or show_index < restore_index:
        fail(f"{rel(dialog_path)} must apply child geometry/restored state before obj.show().")


def check_runtime_guards() -> None:
    legacy = PREBUILT / TAG
    if legacy.exists():
        fail(f"Legacy unqualified native prebuilt exists and can confuse testing: {rel(legacy)}")

    allow_legacy = os.environ.get("FRAMELESS_NATIVE_ALLOW_LEGACY_PREBUILT", "").strip().lower()
    if allow_legacy in {"1", "true", "yes", "on"}:
        fail("FRAMELESS_NATIVE_ALLOW_LEGACY_PREBUILT is enabled; this can load obsolete DLLs.")

    for name in ("FRAMELESS_NATIVE_VARIANT", "FRAMELESS_FORCE_CUSTOM_CHROME", "FRAMELESS_FORCE_SYSTEM_CHROME"):
        value = os.environ.get(name, "").strip()
        if value:
            warn(f"{name}={value!r} overrides normal policy; only use it for targeted diagnostics.")


def check_prebuilt(require_prebuilt: bool) -> None:
    source_files = [
        NATIVE_SRC / "native_window_agent.cpp",
        NATIVE_SRC / "native_window_agent.h",
        NATIVE_SRC / "external_shadow_controller.cpp",
        NATIVE_SRC / "external_shadow_controller.h",
        ROOT / "app" / "cpp" / "frameless_native" / "CMakeLists.txt",
    ]
    newest_source = max(p.stat().st_mtime for p in source_files if p.exists())

    for variant in ("system", "custom"):
        base = PREBUILT / f"{TAG}-{variant}" / "qml" / "FramelessNative"
        dll = base / "FramelessNative.dll"
        qmldir = base / "qmldir"
        if not base.exists():
            if require_prebuilt:
                fail(f"Missing {variant} native module directory: {rel(base)}")
            else:
                warn(f"{variant} native module is not built yet: {rel(base)}")
            continue
        if not dll.exists():
            if require_prebuilt:
                fail(f"Missing {variant} DLL: {rel(dll)}")
            else:
                warn(f"Missing {variant} DLL before build: {rel(dll)}")
        elif dll.stat().st_mtime < newest_source:
            message = f"Stale {variant} DLL: {rel(dll)} is older than native sources."
            if require_prebuilt:
                fail(message)
            else:
                warn(message)
        if not qmldir.exists():
            if require_prebuilt:
                fail(f"Missing {variant} qmldir: {rel(qmldir)}")
            else:
                warn(f"Missing {variant} qmldir before build: {rel(qmldir)}")


def print_runtime_summary() -> None:
    try:
        sys.path.insert(0, str(ROOT))
        from app.native.runtime import native_import_candidates, native_runtime_available, native_runtime_variant
        from app.window_policy import current_window_policy

        policy = current_window_policy()
        print(f"policy={policy}")
        print(f"variant={native_runtime_variant()}")
        print(f"native_available={native_runtime_available(ROOT)}")
        existing = [p for p in native_import_candidates(ROOT) if (p / "FramelessNative" / "qmldir").exists()]
        for path in existing:
            print(f"candidate={rel(path)}")
    except Exception as exc:
        warn(f"Runtime policy summary failed: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check native window source/build integrity.")
    parser.add_argument("--require-prebuilt", action="store_true", help="Require system/custom native DLL outputs to exist and be fresh.")
    parser.add_argument("--summary", action="store_true", help="Print current runtime policy and candidate paths.")
    args = parser.parse_args()

    check_native_agent()
    check_external_shadow()
    check_qml_shadow_path()
    check_runtime_guards()
    check_prebuilt(args.require_prebuilt)
    if args.summary:
        print_runtime_summary()

    for message in WARNINGS:
        print(f"WARN: {message}")
    if ERRORS:
        for message in ERRORS:
            print(f"ERROR: {message}")
        return 1
    print("native window integrity check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())



