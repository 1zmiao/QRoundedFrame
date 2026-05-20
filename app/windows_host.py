from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes
from pathlib import Path

from PySide6.QtCore import QObject, Property, QRect, Qt, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QGuiApplication, QSurfaceFormat, QCursor
from PySide6.QtQuickWidgets import QQuickWidget
from PySide6.QtWidgets import QVBoxLayout, QWidget, QApplication


if sys.platform == "win32":
    user32 = ctypes.windll.user32
    dwmapi = ctypes.windll.dwmapi

    WM_NCHITTEST = 0x0084
    WM_NCLBUTTONDOWN = 0x00A1
    WM_NCLBUTTONDBLCLK = 0x00A3
    WM_GETMINMAXINFO = 0x0024
    WM_NCCALCSIZE = 0x0083
    WM_SIZE = 0x0005
    WM_SYSCOMMAND = 0x0112
    SC_MOVE = 0xF010
    HTCLIENT = 1
    HTCAPTION = 2
    HTLEFT = 10
    HTRIGHT = 11
    HTTOP = 12
    HTTOPLEFT = 13
    HTTOPRIGHT = 14
    HTBOTTOM = 15
    HTBOTTOMLEFT = 16
    HTBOTTOMRIGHT = 17
    SW_MAXIMIZE = 3
    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_NOZORDER = 0x0004
    SWP_NOACTIVATE = 0x0010
    SWP_NOOWNERZORDER = 0x0200
    SWP_FRAMECHANGED = 0x0020
    DWMWA_WINDOW_CORNER_PREFERENCE = 33
    DWMWA_BORDER_COLOR = 34
    DWMWCP_ROUND = 2
    DWMWA_COLOR_NONE = 0xFFFFFFFE
    GWL_STYLE = -16
    WS_CAPTION = 0x00C00000
    WS_THICKFRAME = 0x00040000
    WS_MINIMIZEBOX = 0x00020000
    WS_MAXIMIZEBOX = 0x00010000

    class MARGINS(ctypes.Structure):
        _fields_ = [("cxLeftWidth", ctypes.c_int), ("cxRightWidth", ctypes.c_int), ("cyTopHeight", ctypes.c_int), ("cyBottomHeight", ctypes.c_int)]

    class MSG(ctypes.Structure):
        _fields_ = [
            ("hwnd", wintypes.HWND),
            ("message", wintypes.UINT),
            ("wParam", wintypes.WPARAM),
            ("lParam", wintypes.LPARAM),
            ("time", wintypes.DWORD),
            ("pt", wintypes.POINT),
        ]

    class WINDOWPLACEMENT(ctypes.Structure):
        _fields_ = [
            ("length", wintypes.UINT),
            ("flags", wintypes.UINT),
            ("showCmd", wintypes.UINT),
            ("ptMinPosition", wintypes.POINT),
            ("ptMaxPosition", wintypes.POINT),
            ("rcNormalPosition", wintypes.RECT),
        ]
else:
    MSG = None


class NativeFramelessHost(QWidget):
    """Windows-only native frameless host for the QML scene.

    The QML scene remains responsible for visuals, menus, pages, theme and storage.
    The QWidget HWND owns resize/move/maximize/snap behavior so Windows can handle
    drag-release, Aero Snap and maximize-drag-restore without Qt Quick geometry hacks.
    """

    maximizedChanged = Signal()
    activeChanged = Signal()
    geometryChanged = Signal()
    alwaysOnTopChanged = Signal(bool)
    toastRequested = Signal(str)

    def __init__(self, app: QApplication, engine, bridge, qml_dir: Path, parent=None):
        super().__init__(parent)
        self._app = app
        self._engine = engine
        self._bridge = bridge
        self._qml_dir = Path(qml_dir)
        self._resize_border = 7
        self._normal_geometry = QRect(160, 90, 1080, 700)
        self._normal_frame_geometry = QRect(self._normal_geometry)
        self._move_state: dict | None = None
        self._snap_margin = 14
        self._always_on_top = False
        self._title = "QML 无边框框架"
        self.setProperty("windowKey", "main")
        self.setWindowTitle(self._title)
        self.setMinimumSize(640, 420)
        self.resize(1080, 700)
        self.setWindowFlags(Qt.WindowType.Window | Qt.WindowType.FramelessWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground, True)

        self._quick = QQuickWidget(engine, self)
        self._quick.setResizeMode(QQuickWidget.ResizeMode.SizeRootObjectToView)
        self._quick.setClearColor(QColor(0, 0, 0, 0))
        self._quick.rootContext().setContextProperty("NativeHost", self)
        self._quick.rootContext().setContextProperty("App", bridge)
        self._quick.engine().addImportPath(str(self._qml_dir))

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self._quick)

        self._move_timer = QTimer(self)
        self._move_timer.setInterval(12)
        self._move_timer.timeout.connect(self._tick_system_move)

        self._restore_geometry_from_settings()
        self._quick.setSource(QUrl.fromLocalFile(str(self._qml_dir / "NativeMainContent.qml")))

    @Property(bool, notify=maximizedChanged)
    def maximized(self) -> bool:
        return bool(self.isMaximized() or self.isFullScreen())

    @Property(bool, notify=activeChanged)
    def active(self) -> bool:
        return bool(self.isActiveWindow())

    @Property(bool, notify=alwaysOnTopChanged)
    def alwaysOnTop(self) -> bool:
        return self._always_on_top

    @Property(int, notify=geometryChanged)
    def x(self) -> int:  # for ChildWindow positioning compatibility
        return int(self.geometry().x())

    @Property(int, notify=geometryChanged)
    def y(self) -> int:
        return int(self.geometry().y())

    @Property(int, notify=geometryChanged)
    def width(self) -> int:
        return int(self.geometry().width())

    @Property(int, notify=geometryChanged)
    def height(self) -> int:
        return int(self.geometry().height())


    @Slot(result=bool)
    def isMaximizedState(self) -> bool:
        return bool(self.isMaximized() or self.isFullScreen())

    @Slot()
    @Slot(float, float)
    def beginSystemMove(self, local_x: float = -1.0, local_y: float = -1.0) -> None:
        if sys.platform != "win32":
            return
        try:
            if self.isMaximized() or self.isFullScreen() or self._is_snap_geometry():
                self._begin_manual_restore_move(float(local_x), float(local_y))
                return
            self._save_normal_geometry()
            geometry = self.geometry()
            self._move_state = {
                "local_x": float(local_x),
                "local_y": float(local_y),
                "width": int(geometry.width()),
                "height": int(geometry.height()),
            }
            self._ensure_move_timer()
        except Exception:
            pass

    @Slot()
    def updateSystemMove(self) -> None:
        self._apply_system_move()

    def _apply_system_move(self) -> None:
        state = self._move_state
        if not state:
            return
        cursor = QCursor.pos()
        width = int(state["width"])
        height = int(state["height"])
        new_x = int(cursor.x() - float(state["local_x"]))
        new_y = int(cursor.y() - float(state["local_y"]))
        current = self.geometry()
        if new_x == current.x() and new_y == current.y():
            return
        self.setGeometry(new_x, new_y, width, height)
        self._normal_geometry = QRect(new_x, new_y, width, height)
        self.geometryChanged.emit()

    def _ensure_move_timer(self) -> None:
        if not self._move_timer.isActive():
            self._move_timer.start()

    def _tick_system_move(self) -> None:
        if not self._move_state:
            self._move_timer.stop()
            return
        if not bool(QGuiApplication.mouseButtons() & Qt.MouseButton.LeftButton):
            self.endSystemMove()
            return
        self._apply_system_move()

    @Slot()
    def endSystemMove(self) -> None:
        state = self._move_state
        self._move_state = None
        if self._move_timer.isActive():
            self._move_timer.stop()
        if not state:
            return
        target = self._snap_target_for_cursor()
        if target is not None:
            snap_rect, snap_type = target
            self._store_normal_geometry(QRect(self.geometry()))
            if snap_type == "top":
                super().showMaximized()
                self.maximizedChanged.emit()
            else:
                self.setGeometry(snap_rect)
        elif self._should_store_as_normal_geometry():
            self._store_normal_geometry(QRect(self.geometry()))
        self.geometryChanged.emit()

    @Slot()
    def toggleMaximized(self) -> None:
        if self.isMaximized():
            self.showNormal()
        else:
            self._save_normal_geometry()
            self.showMaximized()
        self.maximizedChanged.emit()
        self.geometryChanged.emit()

    @Slot()
    def showMinimizedNative(self) -> None:
        self.showMinimized()

    @Slot()
    def closeWindow(self) -> None:
        try:
            if self._bridge.tray.handleClosing(self):
                return
        except Exception:
            pass
        try:
            self._bridge.dialogs.closeAll()
        except Exception:
            pass
        self.close()

    @Slot(bool)
    def setAlwaysOnTop(self, enabled: bool) -> None:
        enabled = bool(enabled)
        if enabled == self._always_on_top:
            return
        self._always_on_top = enabled
        if sys.platform == "win32":
            try:
                HWND_TOPMOST = -1
                HWND_NOTOPMOST = -2
                flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
                user32.SetWindowPos(wintypes.HWND(int(self.winId())), HWND_TOPMOST if enabled else HWND_NOTOPMOST, 0, 0, 0, 0, flags)
            except Exception:
                pass
        else:
            flags = self.windowFlags()
            if enabled:
                flags |= Qt.WindowType.WindowStaysOnTopHint
            else:
                flags &= ~Qt.WindowType.WindowStaysOnTopHint
            was_visible = self.isVisible()
            self.setWindowFlags(flags)
            if was_visible:
                self.show()
                self.raise_()
                self.activateWindow()
        self.alwaysOnTopChanged.emit(enabled)

    @Slot()
    def activateHost(self) -> None:
        self.raise_()
        self.activateWindow()

    @Slot(str)
    def showToast(self, message: str) -> None:
        self.toastRequested.emit(str(message))

    @Slot(str, int, int)
    def changeThemeWithRipple(self, next_mode: str, x: int, y: int) -> None:
        try:
            self._bridge.theme.setRippleOrigin(int(x), int(y))
            self._bridge.theme.setMode(str(next_mode))
        except Exception:
            pass

    def showNormal(self):  # noqa: N802 - Qt API compatibility
        super().showNormal()
        self.maximizedChanged.emit()
        self.geometryChanged.emit()

    def showMaximized(self):  # noqa: N802
        self._save_normal_geometry(force=True)
        super().showMaximized()
        self.maximizedChanged.emit()
        self.geometryChanged.emit()

    def moveEvent(self, event):  # noqa: N802
        if self._should_store_as_normal_geometry():
            self._store_normal_geometry(QRect(self.geometry()))
        self.geometryChanged.emit()
        return super().moveEvent(event)

    def resizeEvent(self, event):  # noqa: N802
        if self._should_store_as_normal_geometry():
            self._store_normal_geometry(QRect(self.geometry()))
        self.maximizedChanged.emit()
        self.geometryChanged.emit()
        return super().resizeEvent(event)

    def changeEvent(self, event):  # noqa: N802
        super().changeEvent(event)
        self.maximizedChanged.emit()
        self.activeChanged.emit()

    def closeEvent(self, event):  # noqa: N802
        self._save_normal_geometry()
        self._save_geometry_to_settings()
        try:
            self._bridge.dialogs.closeAll()
        except Exception:
            pass
        return super().closeEvent(event)

    def showEvent(self, event):  # noqa: N802
        super().showEvent(event)
        self._apply_windows_chrome()
        self.maximizedChanged.emit()
        self.activeChanged.emit()

    def nativeEvent(self, event_type, message):  # noqa: N802
        if sys.platform != "win32" or MSG is None:
            return False, 0
        try:
            msg = MSG.from_address(int(message))
        except Exception:
            return False, 0
        if msg.message == WM_NCCALCSIZE:
            return True, 0
        if msg.message == WM_NCHITTEST:
            hit = self._hit_test(int(msg.lParam))
            if hit is not None:
                return True, hit
        return False, 0

    def _make_lparam(self, x: int, y: int) -> int:
        return (int(y) & 0xFFFF) << 16 | (int(x) & 0xFFFF)

    def _hit_test(self, lparam: int):
        if self.isMaximized() or self.isFullScreen():
            return None
        try:
            rect = wintypes.RECT()
            hwnd = wintypes.HWND(int(self.winId()))
            if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
                return None
            x = ctypes.c_short(lparam & 0xFFFF).value
            y = ctypes.c_short((lparam >> 16) & 0xFFFF).value
            try:
                dpi = user32.GetDpiForWindow(hwnd)
                scale = max(1.0, float(dpi) / 96.0)
            except Exception:
                scale = 1.0
            border = max(5, int(round(self._resize_border * scale)))
            left = x < rect.left + border
            right = x >= rect.right - border
            top = y < rect.top + border
            bottom = y >= rect.bottom - border
            if top and left:
                return HTTOPLEFT
            if top and right:
                return HTTOPRIGHT
            if bottom and left:
                return HTBOTTOMLEFT
            if bottom and right:
                return HTBOTTOMRIGHT
            if left:
                return HTLEFT
            if right:
                return HTRIGHT
            if top:
                return HTTOP
            if bottom:
                return HTBOTTOM
        except Exception:
            return None
        return None

    def _apply_windows_chrome(self) -> None:
        if sys.platform != "win32":
            return
        try:
            hwnd = wintypes.HWND(int(self.winId()))
            try:
                style = user32.GetWindowLongW(hwnd, GWL_STYLE)
                style |= WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_CAPTION
                user32.SetWindowLongW(hwnd, GWL_STYLE, style)
            except Exception:
                pass
            pref = ctypes.c_int(DWMWCP_ROUND)
            dwmapi.DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ctypes.byref(pref), ctypes.sizeof(pref))
            try:
                border_color = ctypes.c_uint(DWMWA_COLOR_NONE)
                dwmapi.DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, ctypes.byref(border_color), ctypes.sizeof(border_color))
            except Exception:
                pass
            try:
                margins = MARGINS(1, 1, 1, 1)
                dwmapi.DwmExtendFrameIntoClientArea(hwnd, ctypes.byref(margins))
            except Exception:
                pass
        except Exception:
            pass

    def _restore_geometry_from_settings(self) -> None:
        settings = self._bridge.settings
        saved = settings.value_py("windows/main/normalGeometry", None)
        if isinstance(saved, dict):
            try:
                rect = QRect(int(saved.get("x", 160)), int(saved.get("y", 90)), int(saved.get("w", 1080)), int(saved.get("h", 700)))
                if rect.width() >= 640 and rect.height() >= 420:
                    self._normal_geometry = QRect(rect)
                    self._normal_frame_geometry = QRect(rect)
                    self.setGeometry(rect)
            except Exception:
                pass

    def _screen_available_geometry(self):
        try:
            screen = self.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
            return screen.availableGeometry() if screen is not None else None
        except Exception:
            return None

    def _is_snap_geometry(self, rect: QRect | None = None) -> bool:
        rect = QRect(rect or self.geometry())
        area = self._screen_available_geometry()
        if area is None:
            return False
        tol = 8
        same_height = abs(rect.y() - area.y()) <= tol and abs(rect.height() - area.height()) <= tol
        left_half = abs(rect.x() - area.x()) <= tol and abs(rect.width() - area.width() / 2) <= max(tol, area.width() * 0.04)
        right_half = abs(rect.right() - area.right()) <= tol and abs(rect.width() - area.width() / 2) <= max(tol, area.width() * 0.04)
        near_full = abs(rect.x() - area.x()) <= tol and abs(rect.y() - area.y()) <= tol and abs(rect.width() - area.width()) <= tol and abs(rect.height() - area.height()) <= tol
        return bool(near_full or (same_height and (left_half or right_half)))

    def _should_store_as_normal_geometry(self) -> bool:
        return not self.isMaximized() and not self.isFullScreen() and not self._is_snap_geometry()

    def _save_normal_geometry(self, force: bool = False) -> None:
        if force or self._should_store_as_normal_geometry():
            g = QRect(self.geometry())
            if g.width() >= self.minimumWidth() and g.height() >= self.minimumHeight() and not self._is_snap_geometry(g):
                self._store_normal_geometry(g)

    def _store_normal_geometry(self, candidate: QRect) -> None:
        geom = self._coalesced_normal_geometry(candidate)
        self._normal_geometry = QRect(geom)
        self._remember_normal_frame_geometry(geom)

    def _coalesced_normal_geometry(self, candidate: QRect) -> QRect:
        previous = self._normal_geometry
        if not previous.isValid():
            return QRect(candidate)
        try:
            dw = abs(int(candidate.width()) - int(previous.width()))
            dh = abs(int(candidate.height()) - int(previous.height()))
            if dw <= 32 and dh <= 32:
                return QRect(int(candidate.x()), int(candidate.y()), int(previous.width()), int(previous.height()))
        except Exception:
            pass
        return QRect(candidate)

    def _current_frame_geometry(self) -> QRect:
        if sys.platform == "win32":
            try:
                rect = wintypes.RECT()
                hwnd = wintypes.HWND(int(self.winId()))
                if user32.GetWindowRect(hwnd, ctypes.byref(rect)):
                    return QRect(
                        int(rect.left),
                        int(rect.top),
                        int(rect.right - rect.left),
                        int(rect.bottom - rect.top),
                    )
            except Exception:
                pass
        try:
            frame = self.frameGeometry()
            if frame.isValid():
                return QRect(frame)
        except Exception:
            pass
        return QRect(self.geometry())

    def _remember_normal_frame_geometry(self, client_geom: QRect) -> None:
        frame = self._current_frame_geometry()
        if not frame.isValid():
            return
        try:
            dw = int(frame.width()) - int(client_geom.width())
            dh = int(frame.height()) - int(client_geom.height())
            if abs(dw) <= 96 and abs(dh) <= 96:
                self._normal_frame_geometry = QRect(frame)
        except Exception:
            self._normal_frame_geometry = QRect(frame)

    def _frame_geometry_for_client(self, client_geom: QRect, reference_client: QRect | None = None) -> QRect:
        reference = QRect(reference_client or self._normal_geometry)
        frame = QRect(self._normal_frame_geometry)
        if frame.isValid() and reference.isValid():
            try:
                dx = int(frame.x()) - int(reference.x())
                dy = int(frame.y()) - int(reference.y())
                dw = int(frame.width()) - int(reference.width())
                dh = int(frame.height()) - int(reference.height())
                if abs(dx) <= 96 and abs(dy) <= 96 and abs(dw) <= 128 and abs(dh) <= 128:
                    return QRect(
                        int(client_geom.x()) + dx,
                        int(client_geom.y()) + dy,
                        int(client_geom.width()) + dw,
                        int(client_geom.height()) + dh,
                    )
            except Exception:
                pass
        return QRect(client_geom)

    def _set_restore_bounds_for_client_geometry(self, hwnd: wintypes.HWND, client_geom: QRect) -> QRect:
        outer = self._frame_geometry_for_client(client_geom)
        try:
            placement = WINDOWPLACEMENT()
            placement.length = ctypes.sizeof(WINDOWPLACEMENT)
            if user32.GetWindowPlacement(hwnd, ctypes.byref(placement)):
                placement.rcNormalPosition.left = int(outer.x())
                placement.rcNormalPosition.top = int(outer.y())
                placement.rcNormalPosition.right = int(outer.x() + outer.width())
                placement.rcNormalPosition.bottom = int(outer.y() + outer.height())
                user32.SetWindowPlacement(hwnd, ctypes.byref(placement))
        except Exception:
            pass
        self._normal_frame_geometry = QRect(outer)
        return outer

    def _begin_manual_restore_move(self, local_x: float = -1.0, local_y: float = -1.0) -> None:
        if sys.platform != "win32":
            return
        normal = QRect(self._normal_geometry)
        if not normal.isValid() or normal.width() < self.minimumWidth() or normal.height() < self.minimumHeight():
            normal = QRect(160, 90, 1080, 700)
        try:
            cursor = QCursor.pos()
            ratio_x = 0.5
            current_width = max(1.0, float(self._quick.width() or self.geometry().width()))
            if local_x is not None and local_x >= 0:
                ratio_x = max(0.0, min(1.0, float(local_x) / current_width))
            title_y = int(local_y if local_y is not None and local_y >= 0 else 16)
            title_y = max(6, min(42, title_y))
            new_x = int(cursor.x() - normal.width() * ratio_x)
            new_y = int(cursor.y() - title_y)
            target = QRect(new_x, new_y, normal.width(), normal.height())

            self._set_restore_bounds_for_client_geometry(wintypes.HWND(int(self.winId())), target)
            super().showNormal()
            self.setGeometry(target)
            self._move_state = {
                "local_x": float(cursor.x() - target.x()),
                "local_y": float(cursor.y() - target.y()),
                "width": int(target.width()),
                "height": int(target.height()),
            }
            self._ensure_move_timer()
            self._normal_geometry = QRect(target)
            self._remember_normal_frame_geometry(target)
        except Exception:
            pass
        self.maximizedChanged.emit()
        self.geometryChanged.emit()

    def _snap_target_for_cursor(self) -> tuple[QRect, str] | None:
        area = self._screen_available_geometry()
        if area is None:
            return None
        try:
            cursor = QCursor.pos()
            if cursor.y() <= area.top() + self._snap_margin:
                return QRect(area), "top"
            half_w = max(self.minimumWidth(), area.width() // 2)
            half_w = min(half_w, area.width())
            if cursor.x() <= area.left() + self._snap_margin:
                return QRect(area.left(), area.top(), half_w, area.height()), "left"
            if cursor.x() >= area.right() - self._snap_margin:
                return QRect(area.right() - half_w + 1, area.top(), half_w, area.height()), "right"
        except Exception:
            return None
        return None

    def _save_geometry_to_settings(self) -> None:
        g = self._normal_geometry if self._normal_geometry.isValid() else self.geometry()
        self._bridge.settings.set_value_py("windows/main/normalGeometry", {"x": g.x(), "y": g.y(), "w": g.width(), "h": g.height()})
