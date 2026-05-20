from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QObject, QUrl, Slot
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlEngine

from .util import to_python


class DialogService(QObject):
    def __init__(self, engine: QQmlApplicationEngine, qml_dir: Path, parent=None):
        super().__init__(parent)
        self._engine = engine
        self._qml_dir = qml_dir
        self._windows: dict[int, QObject] = {}
        self._page_windows: dict[str, QObject] = {}
        self._titles = {
            "settings": "设置",
            "tools": "工具",
            "update": "更新",
            "about": "关于",
            "home": "首页",
        }

    @Slot(QObject, str, "QVariant")
    def openChild(self, parent_window, page_key: str, props=None) -> None:
        props = to_python(props) or {}
        existing = self._page_windows.get(page_key)
        if existing is not None:
            try:
                if bool(existing.property("visible")):
                    existing.close()
                    return
            except Exception:
                pass
            self._page_windows.pop(page_key, None)
        page_source = self._page_source(page_key)
        child_source = self._qml_dir / "window" / "ChildWindow.qml"

        # Loading the child window through QQmlApplicationEngine keeps the
        # top-level Window alive as an engine root object. Creating a top-level
        # Window with QQmlComponent can be deleted immediately on some PySide6
        # builds, which is what caused the earlier child-window crash.
        before_count = len(self._engine.rootObjects())
        self._engine.load(QUrl.fromLocalFile(str(child_source)))
        roots = self._engine.rootObjects()
        if len(roots) <= before_count:
            print(f"Failed to load child window: {child_source}")
            return
        obj = roots[-1]

        obj.setProperty("pageSource", page_source)
        obj.setProperty("pageTitle", self._titles.get(page_key, page_key.title()))
        obj.setProperty("windowKey", f"child-{page_key}-{len(self._windows) + 1}")
        if parent_window is not None:
            obj.setProperty("parentWindow", parent_window)
        if isinstance(props, dict):
            for key, value in props.items():
                try:
                    obj.setProperty(str(key), value)
                except Exception:
                    pass

        try:
            QQmlEngine.setObjectOwnership(obj, QQmlEngine.ObjectOwnership.CppOwnership)
        except Exception:
            pass
        obj_id = id(obj)
        self._windows[obj_id] = obj
        self._page_windows[page_key] = obj
        obj.destroyed.connect(lambda *_args, obj_id=obj_id, page_key=page_key: (self._windows.pop(obj_id, None), self._page_windows.pop(page_key, None)))

        try:
            obj.show()
            # Apply configured parent/position after setting parentWindow.
            if hasattr(obj, "applyParentWindow"):
                obj.applyParentWindow()
        except Exception:
            pass


    @Slot()
    def closeAll(self) -> None:
        for obj in list(self._windows.values()):
            try:
                obj.close()
            except Exception:
                pass
        self._windows.clear()
        self._page_windows.clear()

    def _page_source(self, page_key: str) -> str:
        mapping = {
            "home": "HomePage.qml",
            "settings": "SettingsPage.qml",
            "tools": "ToolsPage.qml",
            "update": "UpdatePage.qml",
            "about": "AboutPage.qml",
        }
        filename = mapping.get(page_key, "AboutPage.qml")
        return QUrl.fromLocalFile(str(self._qml_dir / "pages" / filename)).toString()
