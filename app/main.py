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

    bridge = AppBridge(app=app, engine=engine, qml_dir=qml_dir, parent=app)
    engine.rootContext().setContextProperty("App", bridge)

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
