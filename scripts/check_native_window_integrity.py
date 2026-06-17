from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SRC = ROOT / "app" / "cpp" / "frameless_native" / "src"
PREBUILT = ROOT / "app" / "prebuilt"
DEFAULT_TAG = "win-x64-qt6.11"

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
        "SetWindowLongPtrW": "Do not rewrite the main HWND style in NativeWindowAgent; QWindowKit owns it.",
        "WS_POPUP": "Do not force WS_POPUP on the main window; it breaks QWindowKit behavior.",
        "WS_CAPTION": "Do not manually add/remove WS_CAPTION in NativeWindowAgent.",
    }
    for needle, reason in forbidden.items():
        if needle in text:
            fail(f"{rel(path)} contains forbidden pattern {needle!r}. {reason}")

    required = [
        "if (!m_customShadow)",
        "QMargins frameMargins(0, 0, 0, 0)",
        "DwmExtendFrameIntoClientArea(hwnd, &margins)",
        "DWMNCRP_ENABLED",
        "QAbstractNativeEventFilter",
        "nativeEventFilter",
        "msg->hwnd != hwnd",
        "WM_ERASEBKGND",
        "FillRect",
        "void NativeWindowAgent::fillWindowBackground()",
        "GetDC(hwnd)",
        "ReleaseDC(hwnd, hdc)",
        "m_inNativeSizeMove",
        "m_window->requestUpdate();",
        "clearWindowRegion();",
        "setShellBackgroundColor",
        "setResizeHitTestInsets",
        "applyWindowRegion(false)",
        "CreateRoundRectRgn",
        "CreateRectRgn",
        "SetWindowRgn(hwnd, region, redrawRegion)",
        "SetWindowRgn(hwnd, nullptr",
    ]
    for needle in required:
        if needle not in text:
            fail(f"{rel(path)} is missing required custom-path guard/code: {needle}")
    if "const DWORD ncPolicy = 1" in text:
        fail(f"{rel(path)} must keep DWM non-client rendering enabled on the custom path; disabling it can expose classic Win10 frame artifacts.")
    resize_start = text.find("case QEvent::Resize:")
    resize_end = text.find("break;", resize_start)
    resize_block = text[resize_start:resize_end] if resize_start >= 0 and resize_end > resize_start else ""
    if "m_inNativeSizeMove" not in resize_block or "fillWindowBackground();" not in resize_block:
        fail(f"{rel(path)} must fill the class background during native interactive resize.")
    if "applyWindowRegion" in resize_block.split("m_inNativeSizeMove", 1)[0]:
        fail(f"{rel(path)} must not update SetWindowRgn before checking native interactive resize state.")
    for forbidden_resize_backing in [
        "resizeBackingWindowClassName",
        "m_resizeBackingHwnd",
        "windowOpaqueBacking",
    ]:
        if forbidden_resize_backing in text:
            fail(f"{rel(path)} must not keep obsolete single-HWND resize-backing experiments: {forbidden_resize_backing}")
    for needle in [
        "Q_PROPERTY(bool nativeSizeMoveActive READ nativeSizeMoveActive NOTIFY nativeSizeMoveActiveChanged)",
        "bool NativeWindowAgent::nativeSizeMoveActive() const",
        "void NativeWindowAgent::setNativeSizeMoveActive(bool active)",
        "emit nativeSizeMoveActiveChanged();",
        "setNativeSizeMoveActive(true);",
        "setNativeSizeMoveActive(false);",
    ]:
        if needle not in text:
            fail(f"{rel(path)} must expose native interactive resize state to QML without resize-backing experiments: {needle}")

    qwk_path = ROOT / "third_party" / "qwindowkit" / "src" / "core" / "contexts" / "win32windowcontext.cpp"
    qwk_text = read_text(qwk_path)
    qwk_forbidden = {
        "syncCustomWindowRegion": "QWindowKit must not own this project's custom region logic.",
        "syncQRoundedFrameRegion": "Do not patch QWindowKit with project-specific live-resize region sync.",
        "frameless-custom-shadow": "Do not branch QWindowKit internals on this project's shadow policy.",
        "frameless-corner-radius": "Do not branch QWindowKit internals on this project's corner policy.",
        "qrounded-full-client-frame": "Do not restore the failed full-client-frame copy-bits experiment.",
    }
    for needle, reason in qwk_forbidden.items():
        if needle in qwk_text:
            fail(f"{rel(qwk_path)} contains project-specific QWindowKit pattern {needle!r}. {reason}")
    qwk_required = [
        "bool realFull = full && !max",
        "qrounded-resize-edge-inset",
        "qrounded-resize-corner-inset",
        'key == QStringLiteral("qrounded-resize-edge-inset")',
        'key == QStringLiteral("qrounded-resize-corner-inset")',
        "nativeWindowPos.x >= 0",
        "nativeWindowPos.y >= 0",
        "nativeWindowPos.x <= windowWidth",
        "nativeWindowPos.y <= windowHeight",
        "isInLeftCornerBorder",
        "isInTopCornerBorder",
        "*result = FALSE",
    ]
    for needle in qwk_required:
        if needle not in qwk_text:
            fail(f"{rel(qwk_path)} is missing required native-window baseline code: {needle}")


def check_native_widget_host_agent() -> None:
    cpp_path = NATIVE_SRC / "native_widget_host_agent.cpp"
    header_path = NATIVE_SRC / "native_widget_host_agent.h"
    cmake_path = ROOT / "app" / "cpp" / "frameless_native" / "CMakeLists.txt"
    qml_path = ROOT / "qml" / "NativeMainContent.qml"
    text = read_text(cpp_path) + "\n" + read_text(header_path)

    required = [
        "class NativeWidgetHostAgent",
        "QML_ELEMENT",
        "QAbstractNativeEventFilter",
        "nativeEventFilter",
        "WM_NCHITTEST",
        "WM_NCLBUTTONDOWN",
        "WM_NCCALCSIZE",
        "WM_SIZING",
        "WM_MOVING",
        "WM_WINDOWPOSCHANGING",
        "WM_WINDOWPOSCHANGED",
        "WM_CONTEXTMENU",
        "HTTRANSPARENT",
        "HTTOPLEFT",
        "HTBOTTOMRIGHT",
        "HTREDUCE",
        "HTZOOM",
        "HTCLOSE",
        "filterEnabled",
        "sizingOrPositionChanging",
        "windowPositionChanged",
        "isMaximizedNative",
        "toggleMaximizedNative",
        "showMinimizedNative",
        "activateNative",
        "setTopMostNative",
        "applyWindowsChromeNative",
        "showMaximizedNative",
        "showNormalNative",
        "beginCaptionMoveNative",
        "setMouseCaptureNative",
        "setWindowGeometryNative",
        "windowFrameGeometryNative",
        "restoreBoundsNative",
        "setRestoreBoundsNative",
        "forceNormalGeometryNative",
        "setShellBackgroundColor",
        "setCornerRadius",
        "applyWindowRegion",
        "CreateRoundRectRgn",
        "SetWindowRgn",
        "WM_ERASEBKGND",
        "FillRect",
        "void NativeWidgetHostAgent::fillHostWindowBackground()",
        "GetDC(hwnd)",
        "ReleaseDC(hwnd, hdc)",
        "case WM_SIZING:\n        fillHostWindowBackground();",
        "case WM_WINDOWPOSCHANGING:\n        fillHostWindowBackground();",
        "case WM_WINDOWPOSCHANGED:\n        fillHostWindowBackground();",
        "DwmSetWindowAttribute",
        "DwmExtendFrameIntoClientArea",
        "captionHitTest",
        "activateWindowBeneathPoint",
        "nativeSizeMoveStarted",
        "nativeSizeMoveFinished",
        "m_inNativeSizeMove",
        "m_inNativeSizeMove = true;",
        "clearWindowRegion(false);",
        "if (!m_inNativeSizeMove) {",
        "case WM_EXITSIZEMOVE:\n        m_inNativeSizeMove = false;\n        applyWindowRegion(false);",
        "case WM_WINDOWPOSCHANGED:\n        fillHostWindowBackground();\n        if (!m_inNativeSizeMove) {\n            applyWindowRegion(false);\n        }\n        emit windowPositionChanged();",
    ]
    for needle in required:
        if needle not in text:
            fail(f"{rel(cpp_path)} is missing required native widget host behavior: {needle}")

    cmake_text = read_text(cmake_path)
    for needle in ["src/native_widget_host_agent.h", "src/native_widget_host_agent.cpp"]:
        if needle not in cmake_text:
            fail(f"{rel(cmake_path)} does not compile {needle}.")

    qml_text = read_text(qml_path)
    for needle in [
        "import FramelessNative 1.0",
        "NativeWidgetHostAgent",
        "hostHwnd",
        "NativeHost.nativeHwnd",
        "filterEnabled",
        "property int shadowVisualInset: root.inlineShadowVisible ? root.normalShadowVisualInset : 0",
        "onSizingOrPositionChanging",
        "onMoving",
        "onWindowPositionChanged",
        "NativeHost.setNativeWidgetAgentReady",
        "nativeWidgetHostAgent.setShellBackgroundColor",
        "NativeHost.setShellBackgroundColor",
        "onNativeSizeMoveStarted",
        "onNativeSizeMoveFinished",
        "property bool nativeSizeMoveActive: false",
        "root.nativeSizeMoveActive = true",
        "root.nativeSizeMoveActive = false",
        "NativeHost.setNativeSizeMoveActive(true)",
        "NativeHost.setNativeSizeMoveActive(false)",
        "border.width: (root.nativeMaximized || root.nativeSizeMoveActive) ? 0 : root.stableHairline",
        "visible: !root.nativeSizeMoveActive",
        "root.syncNativeState()",
        "NativeHost.refreshWindowsChrome",
        "function onNativeShown()",
        "ExternalShadowController",
        "property bool nativeExternalShadow: root.nativeCustomShadow && Qt.platform.os === \"windows\"",
        "property bool inlineShadowVisible: root.nativeCustomShadow",
        "&& !root.nativeExternalShadow",
        "property bool nativeExternalShadowEnabled",
        "externalShadow.setNativeShadowForHwnd",
        "externalShadow.syncNativeShadowForHwnd",
        "externalShadow.destroyNativeShadowForHwnd",
        "Component.onDestruction: root.cleanupExternalShadow()",
    ]:
        if needle not in qml_text:
            fail(f"{rel(qml_path)} is missing NativeWidgetHostAgent integration: {needle}")


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
        "liveCacheSlackPx",
        "ensureNativeShadowBitmap",
        "cachedBitmapSize",
        "sizingEdgeTouchesLeft",
        "sizingEdgeTouchesTop",
        "sizingEdge",
        "guardPx",
        "renderNativeShadowBitmap(state, shadowRect.size(), marginPx, guardPx, innerOverlapPx, opacityScale)",
        "painter.drawImage(dCenter, source, sCenter)",
        "showFlag",
        "state.openingOpacityScale = 0.16",
        "advanceOpeningFade(targetId, 1)",
        "static constexpr int kFadeFrames = 8",
        "targetHwnd",
        "setNativeShadowForHwnd",
        "syncNativeShadowForHwnd",
        "destroyNativeShadowForHwnd",
        "isSnappedHwnd",
        "nativeTargetId",
        "parseHwnd",
        "MA_NOACTIVATEANDEAT",
        "WS_POPUP | WS_DISABLED",
    ]
    for needle in required:
        if needle not in text:
            fail(f"{rel(path)} is missing required external-shadow behavior: {needle}")
    if "GWLP_HWNDPARENT" in text:
        fail(f"{rel(path)} must keep native shadow helpers unowned; owned popups can flash above their owner on Win10.")

    forbidden = {
        "alphaProfile": "Do not synthesize a custom alpha curve; native custom shadow must render the PNG asset.",
        "innerCutoff": "Do not draw shadow into the content area.",
        "qRgba(0, 0, 0, alpha)": "Do not procedurally generate a replacement shadow bitmap.",
        "hideNativeShadow(it.value())": "Do not hide the native shadow during WM_SIZING; it must stay visible while resizing.",
        "if (state.sizing)": "Do not suppress native shadow visibility while sizing.",
        "innerGuardPx": "Do not draw extra center/guard overlays; the PNG asset owns all shadow pixels.",
        "hiddenExtra": "Do not draw extra hidden guard strips behind the window; this creates hard seams and square intersections.",
        "CompositionMode_Source": "Do not overwrite layered-window pixels with a procedural center fill.",
        "painter.fillRect(dCenter, state.centerColor)": "Do not fill the native shadow center with a theme rectangle; render the original PNG center to avoid a cut-out box.",
        "applyNativeShadowRegion": "Do not clip the native shadow center to fix resize black fill; the black fill belongs to the main HWND resize path.",
        "SetWindowRgn(shadow": "Do not cut a hole in the native shadow HWND; center fill intentionally masks helper resize lag.",
        "CombineRgn(outer, outer, inner, RGN_DIFF)": "Do not subtract the target content area from the native shadow helper.",
        "innerKeepPx": "Do not add a shadow-center clipping inset; keep the designed center fill intact.",
    }
    for needle, reason in forbidden.items():
        if needle in text:
            fail(f"{rel(path)} contains forbidden external-shadow pattern {needle!r}. {reason}")

    if "break;    case" in text:
        fail(f"{rel(path)} contains collapsed switch case text: 'break;    case'.")


def check_qml_shadow_path() -> None:
    path = ROOT / "qml" / "window" / "AppWindow.qml"
    text = read_text(path)
    required = [
        "property bool nativeExternalShadow: customExternalShadow && Qt.platform.os === \"windows\"",
        "property bool qmlExternalShadow: customExternalShadow",
        "&& !nativeExternalShadow",
        "&& !linuxCsdShadow",
        "| Qt.WindowSystemMenuHint",
        "| Qt.WindowMinimizeButtonHint",
        "| Qt.WindowMaximizeButtonHint",
        "| Qt.FramelessWindowHint",
        "(root.customExternalShadow ? Qt.NoDropShadowWindowHint : 0)",
        "targetWindow: (root.qmlExternalShadow && root.customShadowEnabled) ? root : null",
        "externalShadow.destroyNativeShadow(root)",
        "Core.Theme.color.surface",
        "root.scheduleNativeShadowShow()",
        "id: stableNativeShadowSyncTimer",
        "Component.onDestruction: root.cleanupExternalShadow()",
        "root.bridge.window.isSnappedState(root)",
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

    theme_path = ROOT / "qml" / "core" / "Theme.qml"
    theme_text = read_text(theme_path)
    for needle in [
        'function baseSurfaceForMode(nextMode) { return Qt.color(',
        'function baseSurfaceAltForMode(nextMode) { return Qt.color(',
        'function baseCardForMode(nextMode) { return Qt.color(',
        'function baseOutlineForMode(nextMode) { return Qt.color(',
    ]:
        if needle not in theme_text:
            fail(f"{rel(theme_path)} must return real QColor values for preview mixing; string colors make the day-theme ripple render dark.")

    ripple_path = ROOT / "qml" / "controls" / "BackgroundRipple.qml"
    ripple_text = read_text(ripple_path)
    if "colorRole: root.colorRole" not in ripple_text:
        fail(f"{rel(ripple_path)} must pass colorRole through to ThemeTransitionLayer so card/sidebar/titlebar ripples use the right surface.")

    legacy_child_path = ROOT / "qml" / "window" / "FramelessWindow.qml"
    legacy_child_text = read_text(legacy_child_path)
    if "snapPreview.showAt" in legacy_child_text:
        fail(f"{rel(legacy_child_path)} must not show the legacy QML snap preview; native/system snap owns this feedback.")

    cpp_ui_header = ROOT / "app" / "cpp" / "ui_runtime" / "src" / "runtime_app.h"
    cpp_ui_impl = ROOT / "app" / "cpp" / "ui_runtime" / "src" / "runtime_app.cpp"
    cpp_ui_main = ROOT / "app" / "cpp" / "ui_runtime" / "src" / "main.cpp"
    cpp_ui_cmake = ROOT / "app" / "cpp" / "ui_runtime" / "CMakeLists.txt"
    cpp_ui_text = read_text(cpp_ui_header) + "\n" + read_text(cpp_ui_impl) + "\n" + read_text(cpp_ui_main)
    for needle in [
        "Q_PROPERTY(QObject *settings READ settings CONSTANT)",
        "Q_PROPERTY(QObject *theme READ theme CONSTANT)",
        "Q_PROPERTY(QObject *performance READ performance CONSTANT)",
        "Q_PROPERTY(QObject *tray READ tray CONSTANT)",
        "Q_PROPERTY(QObject *window READ window CONSTANT)",
        "Q_PROPERTY(QObject *dialogs READ dialogs CONSTANT)",
        "Q_PROPERTY(QObject *secrets READ secrets CONSTANT)",
        "Q_PROPERTY(QObject *taskStore READ taskStore CONSTANT)",
        "Q_INVOKABLE QVariantMap memorySample(bool includeWorkingSetPrivate = true) const;",
        "Q_INVOKABLE QVariantMap callWorker(const QString &method, const QVariantMap &payload = {}) const;",
        "Q_INVOKABLE bool copyText(const QString &text);",
        "Q_INVOKABLE bool copyToClipboard(const QString &text);",
        "QClipboard *clipboard = QGuiApplication::clipboard();",
        "Q_PROPERTY(QString effectiveProfile READ effectiveProfile NOTIFY effectiveProfileChanged)",
        "Q_INVOKABLE void setLowMemoryMode(bool enabled);",
        "Q_INVOKABLE int totalMemoryMb() const;",
        "QString RuntimePerformance::computeEffectiveProfile() const",
        "totalPhysicalMemoryMb()",
        "Q_INVOKABLE void remove(const QString &key);",
        "removeNestedValueRecursive",
        "Q_INVOKABLE void prepareChild(const QString &pageKey);",
        "Q_INVOKABLE void openChild(QObject *parentWindow, const QString &pageKey, const QVariant &properties);",
        "QQmlComponent(engine, pageUrl, QQmlComponent::PreferSynchronous, this)",
        "QROUNDEDFRAME_ROOT",
        "configureProcessAllocator();",
        "mallopt(M_TRIM_THRESHOLD",
        "setDefaultEnv(\"QT_QUICK_BACKEND\", \"software\")",
    ]:
        if needle not in cpp_ui_text:
            fail(f"C++ UI runtime is missing migrated bridge/runtime behavior: {needle}")
    launcher_path = ROOT / "app" / "cpp_ui_launcher.py"
    launcher_text = read_text(launcher_path)
    if 'env.setdefault("QROUNDEDFRAME_ROOT"' in launcher_text:
        fail(f"{rel(launcher_path)} must overwrite QROUNDEDFRAME_ROOT; copied projects must not inherit another project root.")
    if 'env["QROUNDEDFRAME_ROOT"] = str(ROOT)' not in launcher_text:
        fail(f"{rel(launcher_path)} must set QROUNDEDFRAME_ROOT from its own repository root.")
    if 'absoluteFilePath(QStringLiteral("../../.."))' in read_text(cpp_ui_main):
        fail(f"{rel(cpp_ui_main)} must not rely on fixed ../../../ runtime-root fallback; build/package layouts differ.")
    if "for (int i = 0; i < 10; ++i)" not in read_text(cpp_ui_main):
        fail(f"{rel(cpp_ui_main)} must search upward for the runtime root so backups can run independently.")
    for rel_script in [
        "app/cpp/ui_runtime/run_linux.sh",
        "scripts/package_app.py",
    ]:
        script_text = read_text(ROOT / rel_script)
        if "${QROUNDEDFRAME_ROOT:-" in script_text:
            fail(f"{rel_script} must not preserve an inherited QROUNDEDFRAME_ROOT.")
    launcher_cpp_text = read_text(ROOT / "app" / "cpp" / "launcher" / "launcher.cpp")
    if 'SetEnvironmentVariableW(L"QROUNDEDFRAME_ROOT", runtimeDir.c_str())' not in launcher_cpp_text:
        fail("Windows launcher must set QROUNDEDFRAME_ROOT to its bundled runtime directory.")
    for forbidden in [
        "QQuickWidget",
        "createWindowContainer",
        "app/bridge",
        "legacy_pyside_ui",
    ]:
        if forbidden in read_text(cpp_ui_cmake) or forbidden in cpp_ui_text:
            fail(f"C++ UI runtime must not depend on obsolete PySide/QWidget fallback path: {forbidden}")

    native_agent_path = NATIVE_SRC / "native_window_agent.cpp"
    native_agent_text = read_text(native_agent_path)
    native_agent_header = read_text(NATIVE_SRC / "native_window_agent.h")
    theme_text = read_text(ROOT / "qml" / "core" / "Theme.qml")
    if "int m_resizeEdgeInset = 6;" not in native_agent_header or "int m_resizeCornerInset = 8;" not in native_agent_header:
        fail(f"{rel(native_agent_path)} must default QWindowKit resize hit testing to 6px edges and 8px corners.")
    if "property int resizeEdgeInset: 6" not in theme_text or "property int resizeCornerInset: 8" not in theme_text:
        fail("qml/core/Theme.qml must expose 6px edges and 8px corners for resize hit testing.")
    for needle in [
        "m_resizeEdgeInset",
        "m_resizeCornerInset",
        "updateClassBackgroundBrush",
        "restoreClassBackgroundBrush",
        "SetClassLongPtrW(hwnd, GCLP_HBRBACKGROUND",
        "InvalidateRect(hwnd, nullptr, FALSE)",
        "case WM_ERASEBKGND: {\n        if (msg->hwnd != hwnd)",
        "case WM_ENTERSIZEMOVE:",
        "case WM_SIZING:",
        "case WM_WINDOWPOSCHANGING:",
        "case WM_WINDOWPOSCHANGED:",
    ]:
        if needle not in native_agent_text:
            fail(f"{rel(native_agent_path)} must store project resize hit-test settings: {needle}")
    for needle in [
        "fillExposedResizeStrips",
        "fillExposedResizeBands",
        "emitLiveResizeTargetForNativeSize",
        "liveResizeTargetChanged",
        "m_lastClientPaintRect",
        "m_lastWindowRect",
        "m_hasLastWindowRect",
    ]:
        if needle in native_agent_text:
            fail(f"{rel(native_agent_path)} must not add GDI/live-resize repaint loops on top of QWindowKit's native resize path: {needle}")
    for forbidden in [
        "case WM_SIZING: {\n        fillWindowBackground();\n        m_window->requestUpdate();",
        "case WM_WINDOWPOSCHANGING: {\n        fillWindowBackground();\n        WINDOWPOS *pos = reinterpret_cast<WINDOWPOS *>(msg->lParam);\n        m_window->requestUpdate();",
    ]:
        if forbidden in native_agent_text:
            fail(f"{rel(native_agent_path)} must not force Qt Quick requestUpdate from high-frequency live-resize messages: {forbidden}")

    app_window_path = ROOT / "qml" / "window" / "AppWindow.qml"
    app_window_text = read_text(app_window_path)
    if "id: nativeResizeBackdrop" in app_window_text or "nativeLiveResizeBackdropWidth" in app_window_text:
        fail(f"{rel(app_window_path)} must not paint a QML live-resize backdrop; it hides real content with solid theme color during fast resize.")
    if "id: background" not in app_window_text or "anchors.fill: parent" not in app_window_text:
        fail(f"{rel(app_window_path)} must keep the normal window background anchored to the actual QML window size.")
    native_widget_header = NATIVE_SRC / "native_widget_host_agent.h"
    if "qreal m_resizeBorder = 4.0;" not in read_text(native_widget_header):
        fail(f"{rel(native_widget_header)} must default QWidget-host resize hit testing to 4px edges.")

    resize_area_path = ROOT / "qml" / "window" / "ResizeArea.qml"
    resize_area_text = read_text(resize_area_path)
    if "property int grip: 6" not in resize_area_text or "property int cornerGrip: 8" not in resize_area_text:
        fail(f"{rel(resize_area_path)} must keep fallback resize areas at 6px edges and 8px corners.")

    if "snappedVisualKind === \"vertical\" ? normalShadowVisualInset" in legacy_child_text:
        fail(f"{rel(legacy_child_path)} must not keep horizontal shadow margins while snapped; Windows snap divider owns the outer bounds.")

    native_main_path = ROOT / "qml" / "NativeMainContent.qml"
    native_main_text = read_text(native_main_path)
    if "onSizingOrPositionChanging: {\n            if (typeof NativeHost !== \"undefined\" && NativeHost && NativeHost.syncQuickGeometry)\n                NativeHost.syncQuickGeometry()\n            root.syncNativeState()\n            root.syncExternalShadow(false)" in native_main_text:
        fail(f"{rel(native_main_path)} must not re-sync native shadow from QML during WM_SIZING; the C++ native event filter owns live shadow geometry.")
    if "onSizingOrPositionChanging" in native_main_text and "NativeHost.syncQuickGeometry()" in native_main_text:
        fail(f"{rel(native_main_path)} must not force QWidget-host quick geometry from QML during WM_SIZING; QWidget resizeEvent owns committed child geometry.")
    if "onWidthChanged: {\n        Qt.callLater(root.syncNativeHitTestMetrics)\n        root.syncExternalShadow(false)" in native_main_text:
        fail(f"{rel(native_main_path)} must not re-sync native shadow from QML width/height changes during live resize.")

    widget_host_path = NATIVE_SRC / "native_widget_host_agent.cpp"
    widget_host_text = read_text(widget_host_path)
    if "case WM_SIZING:\n        if (msg->lParam)" in widget_host_text:
        fail(f"{rel(widget_host_path)} must not update SetWindowRgn during interactive WM_SIZING; final region correction belongs to WM_EXITSIZEMOVE/WM_WINDOWPOSCHANGED.")


def check_runtime_guards(tag: str) -> None:
    legacy = PREBUILT / tag
    if legacy.exists():
        fail(f"Legacy unqualified native prebuilt exists and can confuse testing: {rel(legacy)}")

    allow_legacy = os.environ.get("FRAMELESS_NATIVE_ALLOW_LEGACY_PREBUILT", "").strip().lower()
    if allow_legacy in {"1", "true", "yes", "on"}:
        fail("FRAMELESS_NATIVE_ALLOW_LEGACY_PREBUILT is enabled; this can load obsolete DLLs.")

    for name in ("FRAMELESS_NATIVE_VARIANT", "FRAMELESS_FORCE_CUSTOM_CHROME", "FRAMELESS_FORCE_SYSTEM_CHROME"):
        value = os.environ.get(name, "").strip()
        if value:
            warn(f"{name}={value!r} overrides normal policy; only use it for targeted diagnostics.")


def check_prebuilt(require_prebuilt: bool, tag: str) -> None:
    source_files = [
        NATIVE_SRC / "native_window_agent.cpp",
        NATIVE_SRC / "native_window_agent.h",
        NATIVE_SRC / "external_shadow_controller.cpp",
        NATIVE_SRC / "external_shadow_controller.h",
        ROOT / "app" / "cpp" / "frameless_native" / "CMakeLists.txt",
    ]
    newest_source = max(p.stat().st_mtime for p in source_files if p.exists())

    for variant in ("system", "custom"):
        base = PREBUILT / f"{tag}-{variant}" / "qml" / "FramelessNative"
        library = base / ("FramelessNative.dll" if sys.platform == "win32" else "libFramelessNative.so")
        qmldir = base / "qmldir"
        if not base.exists():
            if require_prebuilt:
                fail(f"Missing {variant} native module directory: {rel(base)}")
            else:
                warn(f"{variant} native module is not built yet: {rel(base)}")
            continue
        if not library.exists():
            if require_prebuilt:
                fail(f"Missing {variant} native library: {rel(library)}")
            else:
                warn(f"Missing {variant} native library before build: {rel(library)}")
        elif library.stat().st_mtime < newest_source:
            message = f"Stale {variant} native library: {rel(library)} is older than native sources."
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
        from app.window_policy import current_window_policy

        policy = current_window_policy()
        print(f"policy={policy}")
        for variant in ("system", "custom"):
            candidate = PREBUILT / f"{DEFAULT_TAG}-{variant}" / "qml"
            available = (candidate / "FramelessNative" / "qmldir").exists()
            print(f"{variant}_native_available={available}")
            if available:
                print(f"candidate={rel(candidate)}")
    except Exception as exc:
        warn(f"Runtime policy summary failed: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check native window source/build integrity.")
    parser.add_argument("--require-prebuilt", action="store_true", help="Require system/custom native DLL outputs to exist and be fresh.")
    parser.add_argument("--summary", action="store_true", help="Print current runtime policy and candidate paths.")
    parser.add_argument("--tag", default=DEFAULT_TAG, help="Native prebuilt runtime tag to check.")
    args = parser.parse_args()

    check_native_agent()
    check_native_widget_host_agent()
    check_external_shadow()
    check_qml_shadow_path()
    check_runtime_guards(args.tag)
    check_prebuilt(args.require_prebuilt, args.tag)
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
