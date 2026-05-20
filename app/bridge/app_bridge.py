from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QObject, Property, Slot
from PySide6.QtQml import QQmlApplicationEngine

from .dialog_service import DialogService
from .secret_store import SecretStore
from .settings_store import SettingsStore
from .theme_controller import ThemeController
from .tray_controller import TrayController
from .window_controller import WindowController


class AppBridge(QObject):
    def __init__(self, app, engine: QQmlApplicationEngine, qml_dir: Path, parent=None):
        super().__init__(parent)
        self._app = app
        self._settings = SettingsStore()
        self._secrets = SecretStore(password=None)
        self._theme = ThemeController(self._settings)
        self._window = WindowController(self._settings)
        self._dialogs = DialogService(engine=engine, qml_dir=qml_dir)
        self._tray = TrayController(app=app, settings=self._settings, theme=self._theme, project_root=qml_dir.parent, parent=self)

    @Property(QObject, constant=True)
    def settings(self):
        return self._settings

    @Property(QObject, constant=True)
    def secrets(self):
        return self._secrets

    @Property(QObject, constant=True)
    def theme(self):
        return self._theme

    @Property(QObject, constant=True)
    def window(self):
        return self._window

    @Property(QObject, constant=True)
    def dialogs(self):
        return self._dialogs

    @Property(QObject, constant=True)
    def tray(self):
        return self._tray

    @Slot(str)
    def copyToClipboard(self, text: str) -> None:
        clipboard = self._app.clipboard()
        clipboard.setText(str(text))
    @Slot(str)
    def copyText(self, text: str) -> None:
        clipboard = self._app.clipboard()
        if clipboard is not None:
            clipboard.setText(str(text))

