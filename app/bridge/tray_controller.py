from __future__ import annotations

import ctypes
import sys
import time
from ctypes import wintypes
from pathlib import Path

import shiboken6

from PySide6.QtCore import QObject, Property, QTimer, Qt, Signal, Slot, QEvent, QUrl
from PySide6.QtGui import QAction, QColor, QCursor, QGuiApplication, QIcon, QPainter, QPixmap
from PySide6.QtQml import QQmlEngine
from PySide6.QtWidgets import QApplication, QFrame, QGraphicsDropShadowEffect, QHBoxLayout, QLabel, QMenu, QPushButton, QSystemTrayIcon, QVBoxLayout, QWidget

from .util import app_root


class TrayController(QObject):
    minimizeToTrayChanged = Signal(bool)
    trayContextMenuRequested = Signal(int, int)
    trayPrimaryClicked = Signal()
    iconPathChanged = Signal(str)

    def __init__(self, app: QApplication, settings, theme, project_root: Path | None = None, parent=None, engine=None, qml_dir: Path | None = None):
        super().__init__(parent)
        self._app = app
        self._settings = settings
        self._theme = theme
        self._project_root = Path(project_root) if project_root is not None else app_root()
        self._engine = engine
        self._qml_dir = Path(qml_dir) if qml_dir is not None else self._project_root / "qml"
        self._default_icon_path = self._project_root / "resources" / "icons" / "tray_icon.png"
        configured_icon = str(settings.value_py("tray/iconPath", "") or "")
        self._icon_path = Path(configured_icon) if configured_icon else self._default_icon_path
        self._main_window = None
        self._quitting = False
        self._tray: QSystemTrayIcon | None = None
        self._tray_menu: QMenu | None = None
        self._last_context_activation = 0.0
        self._qml_tray_menu = None
        self._tray_menu_widget = None
        self._minimize_to_tray = bool(settings.value_py("window/closeToTray", settings.value_py("window/minimizeToTray", False)))
        try:
            self._theme.primaryColorChanged.connect(lambda _c: self._update_icon())
        except Exception:
            pass
        self._ensure_tray()

    @Property(bool, notify=minimizeToTrayChanged)
    def minimizeToTray(self) -> bool:
        return self._minimize_to_tray

    @Property(bool, notify=minimizeToTrayChanged)
    def closeToTray(self) -> bool:
        return self._minimize_to_tray

    @Property(str, notify=iconPathChanged)
    def iconPath(self) -> str:
        return str(self._icon_path)

    @Slot(result=str)
    def defaultIconPath(self) -> str:
        return str(self._default_icon_path)

    @Slot(str)
    def setIconPath(self, path: str) -> None:
        self._icon_path = Path(path) if path else self._default_icon_path
        self._settings.set_value_py("tray/iconPath", "" if self._icon_path == self._default_icon_path else str(self._icon_path))
        self.iconPathChanged.emit(str(self._icon_path))
        self._update_icon()

    @Slot(bool)
    def setCloseToTray(self, enabled: bool) -> None:
        self.setMinimizeToTray(enabled)

    @Slot(bool)
    def setMinimizeToTray(self, enabled: bool) -> None:
        enabled = bool(enabled)
        if enabled == self._minimize_to_tray:
            return
        self._minimize_to_tray = enabled
        self._settings.set_value_py("window/closeToTray", enabled)
        self._settings.set_value_py("window/minimizeToTray", enabled)
        if enabled:
            self._ensure_tray()
        self.minimizeToTrayChanged.emit(enabled)

    @Slot(QObject)
    def registerWindow(self, win) -> None:
        self._main_window = win
        self._ensure_tray()

    @Slot(QObject, result=bool)
    def minimizeWindow(self, win) -> bool:
        if not self._minimize_to_tray:
            return False
        if self._window_key(win) != "main":
            return False
        if not self._ensure_tray():
            return False
        self._main_window = win
        QTimer.singleShot(0, win.hide)
        try:
            self._tray.show()
        except Exception:
            pass
        return True

    @Slot(QObject, result=bool)
    def handleClosing(self, win) -> bool:
        if self._quitting:
            return False
        return self.minimizeWindow(win)

    @Slot(int, int, int, int, result=bool)
    def mousePressedOutside(self, x: int, y: int, w: int, h: int) -> bool:
        try:
            if not bool(QGuiApplication.mouseButtons()):
                return False
            pos = QCursor.pos()
            return not (int(x) <= pos.x() <= int(x) + int(w) and int(y) <= pos.y() <= int(y) + int(h))
        except Exception:
            return False

    @Slot(int, int, result="QVariant")
    def availableGeometryAt(self, x: int, y: int):
        try:
            pos = QCursor.pos()
            pos.setX(int(x))
            pos.setY(int(y))
            screen = QGuiApplication.screenAt(pos) or QGuiApplication.primaryScreen()
            area = screen.availableGeometry() if screen is not None else None
            if area is None:
                return {}
            return {"x": area.x(), "y": area.y(), "w": area.width(), "h": area.height()}
        except Exception:
            return {}

    @Slot(QObject)
    def raiseTrayMenuWindow(self, win) -> None:
        if win is None:
            return
        try:
            win.show()
        except Exception:
            pass
        try:
            getattr(win, "raise")()
        except Exception:
            try:
                win.raise_()
            except Exception:
                pass
        self._force_topmost_window(win)

    def _raise_window(self, win) -> None:
        try:
            win.raise_()
        except Exception:
            try:
                getattr(win, "raise")()
            except Exception:
                pass
        try:
            win.requestActivate()
        except Exception:
            try:
                win.activateWindow()
            except Exception:
                pass

    @Slot()
    def showMainWindow(self) -> None:
        win = self._main_window
        if win is None:
            return
        try:
            win.showNormal()
        except Exception:
            try:
                win.show()
            except Exception:
                pass
        self._raise_window(win)


    @Slot()
    def centerMainWindow(self) -> None:
        win = self._main_window
        if win is None:
            return
        try:
            win.showNormal()
        except Exception:
            try:
                win.show()
            except Exception:
                pass
        try:
            screen = None
            try:
                screen = win.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
            except Exception:
                screen = QGuiApplication.primaryScreen()
            area = screen.availableGeometry() if screen is not None else None
            if area is not None:
                try:
                    w = max(1, int(win.width()))
                    h = max(1, int(win.height()))
                except Exception:
                    g = win.geometry()
                    w, h = int(g.width()), int(g.height())
                x = int(area.x() + (area.width() - w) / 2)
                y = int(area.y() + (area.height() - h) / 2)
                try:
                    win.setPosition(x, y)
                except Exception:
                    win.move(x, y)
            self._raise_window(win)
        except Exception:
            self._raise_window(win)

    @Slot()
    def exitApplication(self) -> None:
        if self._quitting:
            return
        self._quitting = True
        QTimer.singleShot(0, self._finish_exit_application)

    def _finish_exit_application(self) -> None:
        self._destroy_qml_context_menu()
        self._destroy_themed_context_menu()
        self._destroy_native_context_menu()
        try:
            if self._main_window is not None:
                self._main_window.close()
        except Exception:
            pass
        self._destroy_tray_icon()
        QTimer.singleShot(0, self._app.quit)

    @Slot()
    def shutdown(self) -> None:
        self._quitting = True
        self._destroy_qml_context_menu()
        self._destroy_themed_context_menu()
        self._destroy_native_context_menu()
        self._destroy_tray_icon()

    def _destroy_tray_icon(self) -> None:
        try:
            if self._tray is not None:
                tray = self._tray
                self._tray = None
                try:
                    tray.activated.disconnect(self._on_activated)
                except Exception:
                    pass
                try:
                    tray.setContextMenu(None)
                except Exception:
                    pass
                self._tray.hide()
                if not self._quitting and shiboken6.isValid(tray):
                    tray.deleteLater()
        except Exception:
            self._tray = None

    def _ensure_tray(self) -> bool:
        if self._tray is not None:
            return True
        try:
            if not QSystemTrayIcon.isSystemTrayAvailable():
                return False
            self._tray = QSystemTrayIcon(self)
            self._tray.setToolTip("QML 无边框框架")
            self._tray.setIcon(self._build_icon())
            self._tray.setContextMenu(None)
            self._tray.activated.connect(self._on_activated)
            self._tray.show()
            return True
        except Exception:
            self._tray = None
            return False

    def _update_icon(self) -> None:
        if self._tray is not None:
            self._tray.setIcon(self._build_icon())

    def _build_icon(self) -> QIcon:
        for candidate in (self._icon_path, self._default_icon_path):
            try:
                candidate = Path(candidate)
                if candidate.exists():
                    icon = QIcon(str(candidate))
                    if not icon.isNull():
                        return icon
            except Exception:
                pass

        pix = QPixmap(32, 32)
        pix.fill(QColor(0, 0, 0, 0))
        painter = QPainter(pix)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        color = QColor(str(getattr(self._theme, "primaryColor", "#6750A4")))
        if not color.isValid():
            color = QColor("#6750A4")
        painter.setBrush(color)
        painter.setPen(QColor(255, 255, 255, 210))
        painter.drawRoundedRect(4, 4, 24, 24, 7, 7)
        painter.setPen(QColor(255, 255, 255))
        font = painter.font()
        font.setBold(True)
        font.setPixelSize(16)
        painter.setFont(font)
        painter.drawText(pix.rect(), Qt.AlignmentFlag.AlignCenter, "Q")
        painter.end()
        return QIcon(pix)

    def _reason_value(self, reason) -> int:
        try:
            return int(reason.value)
        except Exception:
            try:
                return int(reason)
            except Exception:
                return -1

    def _on_activated(self, reason) -> None:
        value = self._reason_value(reason)
        context_value = self._reason_value(QSystemTrayIcon.ActivationReason.Context)
        trigger_value = self._reason_value(QSystemTrayIcon.ActivationReason.Trigger)
        double_value = self._reason_value(QSystemTrayIcon.ActivationReason.DoubleClick)

        if value == context_value:
            pos = QCursor.pos()
            self._last_context_activation = time.monotonic()
            if not self._toggle_qml_context_menu(pos):
                self._toggle_themed_context_menu(pos)
            return

        if value in (trigger_value, double_value):
            self._hide_qml_context_menu()
            self._hide_themed_context_menu()
            self.trayPrimaryClicked.emit()
            return

    def _ensure_qml_context_menu(self):
        if self._qml_tray_menu is not None:
            try:
                if shiboken6.isValid(self._qml_tray_menu):
                    return self._qml_tray_menu
            except Exception:
                pass
            self._qml_tray_menu = None
        if self._engine is None:
            return None
        source = self._qml_dir / "controls" / "TrayMenuWindow.qml"
        try:
            before_count = len(self._engine.rootObjects())
            self._engine.load(QUrl.fromLocalFile(str(source)))
            roots = self._engine.rootObjects()
            if len(roots) <= before_count:
                return None
            obj = roots[-1]
            QQmlEngine.setObjectOwnership(obj, QQmlEngine.ObjectOwnership.CppOwnership)
            self._qml_tray_menu = obj
            try:
                obj.destroyed.connect(lambda *_args: setattr(self, "_qml_tray_menu", None))
            except Exception:
                pass
            return obj
        except Exception:
            self._qml_tray_menu = None
            return None

    def _toggle_qml_context_menu(self, pos) -> bool:
        menu = self._ensure_qml_context_menu()
        if menu is None:
            return False
        try:
            self._hide_themed_context_menu()
        except Exception:
            pass
        return self._call_qml_menu(menu, "toggleAt", int(pos.x()), int(pos.y()))

    def _hide_qml_context_menu(self) -> None:
        menu = self._qml_tray_menu
        if menu is None:
            return
        try:
            self._call_qml_menu(menu, "closeMenu")
        except Exception:
            pass

    def _destroy_qml_context_menu(self) -> None:
        menu = self._qml_tray_menu
        self._qml_tray_menu = None
        if menu is None:
            return
        try:
            self._call_qml_menu(menu, "closeMenu")
            if not self._quitting and shiboken6.isValid(menu):
                menu.deleteLater()
        except Exception:
            pass

    def _call_qml_menu(self, menu, method_name: str, *args) -> bool:
        try:
            method = getattr(menu, method_name, None)
            if not callable(method):
                return False
            method(*args)
            return True
        except Exception:
            return False

    def _toggle_themed_context_menu(self, pos) -> None:
        try:
            if self._tray_menu_widget is not None and self._tray_menu_widget.isVisible():
                self._tray_menu_widget.hide()
                return
            self._show_themed_context_menu(pos)
        except Exception:
            self._show_native_context_menu(pos)

    def _hide_themed_context_menu(self) -> None:
        if self._quitting:
            return
        try:
            if self._tray_menu_widget is not None:
                self._tray_menu_widget.hide()
        except Exception:
            pass

    def _destroy_themed_context_menu(self) -> None:
        try:
            if self._tray_menu_widget is not None:
                widget = self._tray_menu_widget
                self._tray_menu_widget = None
                widget.removeEventFilter(self)
                widget.hide()
                widget.close()
                widget.setParent(None)
                if not self._quitting and shiboken6.isValid(widget):
                    widget.deleteLater()
        except Exception:
            self._tray_menu_widget = None

    def _build_native_context_menu(self) -> QMenu:
        if self._tray_menu is not None:
            return self._tray_menu
        menu = QMenu()
        center_action = QAction("居中主窗口", menu)
        quit_action = QAction("退出", menu)
        center_action.triggered.connect(self.centerMainWindow)
        quit_action.triggered.connect(self.exitApplication)
        menu.addAction(center_action)
        menu.addSeparator()
        menu.addAction(quit_action)
        self._apply_menu_style(menu)
        self._tray_menu = menu
        return menu

    def _destroy_native_context_menu(self) -> None:
        menu = self._tray_menu
        self._tray_menu = None
        if menu is None:
            return
        try:
            for action in menu.actions():
                try:
                    action.triggered.disconnect()
                except Exception:
                    pass
            menu.hide()
            menu.setParent(None)
            if not self._quitting and shiboken6.isValid(menu):
                menu.deleteLater()
        except Exception:
            pass

    def _show_themed_context_menu(self, pos) -> None:
        dark = str(getattr(self._theme, "mode", "dark")) == "dark"
        if self._tray_menu_widget is None:
            self._tray_menu_widget = QWidget(None, Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
            self._tray_menu_widget.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
            self._tray_menu_widget.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
            self._tray_menu_widget.installEventFilter(self)

            outer = QVBoxLayout(self._tray_menu_widget)
            outer.setContentsMargins(18, 18, 18, 18)
            outer.setSpacing(0)
            panel = QFrame(self._tray_menu_widget)
            panel.setObjectName("trayPanel")
            outer.addWidget(panel)
            layout = QVBoxLayout(panel)
            layout.setContentsMargins(8, 8, 8, 8)
            layout.setSpacing(5)

            center_btn = QPushButton("  居中主窗口", panel)
            center_btn.setObjectName("trayAction")
            center_btn.clicked.connect(lambda: (self._hide_themed_context_menu(), self.centerMainWindow()))
            exit_btn = QPushButton("  退出", panel)
            exit_btn.setObjectName("trayAction")
            exit_btn.clicked.connect(self.exitApplication)
            line = QFrame(panel)
            line.setObjectName("trayLine")
            line.setFrameShape(QFrame.Shape.HLine)
            layout.addWidget(center_btn)
            layout.addWidget(line)
            layout.addWidget(exit_btn)
            self._tray_menu_widget.resize(214, 142)

        if dark:
            css = """
            QWidget { background: transparent; }
            QFrame#trayPanel { background: #1B1D27; border: 1px solid #4E496B; border-radius: 10px; }
            QPushButton#trayAction { background: transparent; color: #F6F3FF; border: none; border-radius: 7px; padding: 8px 12px; text-align: left; font-size: 13px; }
            QPushButton#trayAction:hover { background: #37324F; }
            QPushButton#trayAction:pressed { background: #443D60; }
            QFrame#trayLine { color: #353143; background: #353143; max-height: 1px; border: none; }
            """
        else:
            css = """
            QWidget { background: transparent; }
            QFrame#trayPanel { background: #FFFFFF; border: 1px solid #C8CEDA; border-radius: 10px; }
            QPushButton#trayAction { background: transparent; color: #202124; border: none; border-radius: 7px; padding: 8px 12px; text-align: left; font-size: 13px; }
            QPushButton#trayAction:hover { background: #DDE6F7; }
            QPushButton#trayAction:pressed { background: #CCD9F0; }
            QFrame#trayLine { color: #E4E7EF; background: #E4E7EF; max-height: 1px; border: none; }
            """
        self._tray_menu_widget.setStyleSheet(css)
        panel = self._tray_menu_widget.findChild(QFrame, "trayPanel")
        if panel is not None:
            effect = panel.graphicsEffect()
            if not isinstance(effect, QGraphicsDropShadowEffect):
                effect = QGraphicsDropShadowEffect(panel)
                panel.setGraphicsEffect(effect)
            effect.setBlurRadius(30 if dark else 26)
            effect.setOffset(0, 5 if dark else 4)
            effect.setColor(QColor(0, 0, 0, 130 if dark else 58))
        self._tray_menu_widget.adjustSize()
        w = max(214, self._tray_menu_widget.width())
        h = max(142, self._tray_menu_widget.height())
        nx = int(pos.x() - w + 8)
        ny = int(pos.y() - h - 8)
        screen = QGuiApplication.screenAt(pos) or QGuiApplication.primaryScreen()
        if screen is not None:
            area = screen.availableGeometry()
            right_limit = area.x() + area.width() - w - 4
            bottom_limit = area.y() + area.height() - h - 4
            nx = max(area.x() + 4, min(nx, right_limit))
            if ny < area.y() + 4:
                ny = int(pos.y() + 8)
            ny = max(area.y() + 4, min(ny, bottom_limit))
        self._tray_menu_widget.setGeometry(nx, ny, w, h)
        self._last_context_activation = time.monotonic()
        self._tray_menu_widget.show()
        self._tray_menu_widget.raise_()
        self._tray_menu_widget.activateWindow()
        self._force_topmost_widget(self._tray_menu_widget)

    def eventFilter(self, obj, event):  # noqa: N802
        if obj is self._tray_menu_widget:
            if self._quitting:
                return False
            if event.type() in (QEvent.Type.WindowDeactivate, QEvent.Type.FocusOut):
                if time.monotonic() - self._last_context_activation < 0.18:
                    return False
                self._hide_themed_context_menu()
        return super().eventFilter(obj, event)

    def _show_native_context_menu(self, pos) -> None:
        menu = self._build_native_context_menu()
        self._apply_menu_style(menu)
        menu.exec(pos)

    def _apply_menu_style(self, menu: QMenu) -> None:
        try:
            dark = str(getattr(self._theme, "mode", "dark")) == "dark"
        except Exception:
            dark = True
        if dark:
            menu.setStyleSheet("QMenu { background: #1B1D27; color: #F2F0FF; border: 1px solid #4E496B; padding: 6px; } QMenu::item { padding: 7px 28px 7px 22px; border-radius: 6px; } QMenu::item:selected { background: #37324F; }")
        else:
            menu.setStyleSheet("QMenu { background: #FFFFFF; color: #202124; border: 1px solid #C8CEDA; padding: 6px; } QMenu::item { padding: 7px 28px 7px 22px; border-radius: 6px; } QMenu::item:selected { background: #DDE6F7; }")

    def _window_key(self, win) -> str:
        try:
            return str(win.property("windowKey") or "")
        except Exception:
            return ""

    def _window_is_visible(self, win) -> bool:
        try:
            return bool(win.isVisible())
        except Exception:
            try:
                return bool(win.property("visible"))
            except Exception:
                return False

    def _force_topmost_widget(self, widget: QWidget) -> None:
        if widget is None:
            return
        try:
            widget.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint, True)
        except Exception:
            pass
        if sys.platform == "win32":
            try:
                hwnd = wintypes.HWND(int(widget.winId()))
                self._set_hwnd_topmost(hwnd)
            except Exception:
                pass

    def _force_topmost_window(self, win) -> None:
        if sys.platform != "win32" or win is None:
            return
        try:
            hwnd = wintypes.HWND(int(win.winId()))
            self._set_hwnd_topmost(hwnd)
        except Exception:
            pass

    def _set_hwnd_topmost(self, hwnd) -> None:
        try:
            HWND_TOPMOST = -1
            SWP_NOMOVE = 0x0002
            SWP_NOSIZE = 0x0001
            SWP_NOACTIVATE = 0x0010
            SWP_SHOWWINDOW = 0x0040
            ctypes.windll.user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW)
        except Exception:
            pass
