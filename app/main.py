from __future__ import annotations

import os
import sys
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QObject, QEvent, QUrl
from PySide6.QtGui import QSurfaceFormat
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from app.bridge.app_bridge import AppBridge
from app.native.runtime import configure_native_runtime, native_runtime_available, native_runtime_variant


class QuickContextMenuFilter(QObject):
    """Suppress built-in QQuick text context menus.

    The QML controls provide their own AppContextMenu. Native QWidget/QMenu
    context menus, including the tray fallback on platforms that use one, are
    not affected because the filter only accepts QQuick* objects.
    """

    def eventFilter(self, obj, event):  # noqa: N802 - Qt override name
        try:
            if event.type() == QEvent.Type.ContextMenu:
                class_name = obj.metaObject().className() if obj is not None else ""
                if "QQuick" in class_name:
                    return True
        except Exception:
            pass
        return super().eventFilter(obj, event)


def main() -> int:
    # Avoid stale compiled QML cache when users replace this template folder during development.
    os.environ.setdefault("QML_DISABLE_DISK_CACHE", "1")
    # QWindowKit's DwmFlush flicker workaround can make Qt Quick content jump
    # during Win10 upper-left live resize with D3D/RHI. Keep native resize owned
    # by Windows/QWindowKit, but let Qt paint on its own frame cadence.
    os.environ.setdefault("QWK_DISABLE_FLICKER_WORKAROUND", "1")

    # Improves the antialiasing quality of transparent rounded QML windows.
    fmt = QSurfaceFormat()
    fmt.setSamples(4)
    QSurfaceFormat.setDefaultFormat(fmt)

    app = QApplication(sys.argv)

    QCoreApplication.setOrganizationName("TemplateCompany")
    QCoreApplication.setOrganizationDomain("template.local")
    QCoreApplication.setApplicationName("FramelessTemplate")

    QQuickStyle.setStyle("Basic")
    app.installEventFilter(QuickContextMenuFilter(app))

    project_root = Path(__file__).resolve().parents[1]
    qml_dir = project_root / "qml"

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(qml_dir))

    use_native_shell = native_runtime_available(project_root)
    if os.environ.get("FRAMELESS_DEBUG_WINDOW_POLICY", "").strip().lower() in {"1", "true", "yes"}:
        try:
            from app.window_policy import current_window_policy

            print("Window policy:", current_window_policy())
            print("Native runtime variant:", native_runtime_variant())
            print("Native runtime available:", use_native_shell)
        except Exception as exc:
            print("Window policy debug failed:", exc)
    if use_native_shell:
        configure_native_runtime(engine, project_root)

    bridge = AppBridge(app=app, engine=engine, qml_dir=qml_dir, parent=app, native_window_shell=use_native_shell)
    engine.rootContext().setContextProperty("App", bridge)

    if use_native_shell:
        engine.load(QUrl.fromLocalFile(str(qml_dir / "NativeAppMain.qml")))
        if engine.rootObjects():
            return app.exec()
        bridge.set_native_window_shell(False)

    if sys.platform == "win32":
        from app.windows_host import NativeFramelessHost
        host = NativeFramelessHost(app=app, engine=engine, bridge=bridge, qml_dir=qml_dir)
        host.show()
    else:
        engine.load(QUrl.fromLocalFile(str(qml_dir / "MainWindow.qml")))
        if not engine.rootObjects():
            return 1

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

