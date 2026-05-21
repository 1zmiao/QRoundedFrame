from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

import shiboken6

from PySide6.QtCore import QAbstractNativeEventFilter, QObject, QRect, QTimer, Qt, Signal, Slot, Property
from PySide6.QtGui import QCursor, QGuiApplication, QWindow


if sys.platform == "win32":
    WM_SYSCOMMAND = 0x0112
    SC_MOVE = 0xF010
    SC_MAXIMIZE = 0xF030
    SC_RESTORE = 0xF120
    HTCAPTION = 2

    class MSG(ctypes.Structure):
        _fields_ = [
            ("hwnd", wintypes.HWND),
            ("message", wintypes.UINT),
            ("wParam", wintypes.WPARAM),
            ("lParam", wintypes.LPARAM),
            ("time", wintypes.DWORD),
            ("pt", wintypes.POINT),
        ]
else:  # pragma: no cover
    MSG = None


class _WindowsHitTestFilter(QAbstractNativeEventFilter):
    WM_NCCALCSIZE = 0x0083
    WM_NCHITTEST = 0x0084
    WM_NCLBUTTONDOWN = 0x00A1

    HTLEFT = 10
    HTRIGHT = 11
    HTTOP = 12
    HTTOPLEFT = 13
    HTTOPRIGHT = 14
    HTBOTTOM = 15
    HTBOTTOMLEFT = 16
    HTBOTTOMRIGHT = 17

    def __init__(self, controller: "WindowController") -> None:
        super().__init__()
        self._controller = controller

    def nativeEventFilter(self, event_type, message):  # pragma: no cover - Windows runtime only
        if sys.platform != "win32" or MSG is None:
            return False, 0
        try:
            msg = MSG.from_address(int(message))
        except Exception:
            return False, 0

        if not getattr(msg, "hwnd", None):
            return False, 0
        try:
            hwnd = int(msg.hwnd)
        except Exception:
            return False, 0
        if not hwnd:
            return False, 0
        win = self._controller._hwnd_to_window.get(hwnd)
        if win is None:
            return False, 0
        if not self._controller._is_valid_window(win):
            self._controller._hwnd_to_window.pop(hwnd, None)
            return False, 0

        if msg.message == self.WM_NCCALCSIZE:
            # Collapse the native non-client area. We keep WS_THICKFRAME for DWM
            # shadow/system behavior, but QML owns the visual chrome.
            return True, 0

        if msg.message == self.WM_NCLBUTTONDOWN:
            try:
                if int(msg.wParam) == HTCAPTION:
                    self._controller.captionPressed.emit(self._controller._key(win))
            except Exception:
                pass
            return False, 0

        if msg.message == self.WM_NCHITTEST:
            # Let Windows own resize and caption dragging.  This avoids the
            # visible lag that can happen when a frameless QML MouseArea drives
            # setGeometry() manually while the scene graph is also relayouting
            # the page content, and it preserves Aero Snap/Snap Assist.
            hit = self._hit_test(hwnd, int(msg.lParam), win)
            if hit is not None:
                return True, int(hit)
            return False, 0
        return False, 0

    def _hit_test(self, hwnd: int, lparam: int, win: QWindow):
        try:
            rect = wintypes.RECT()
            if not ctypes.windll.user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect)):
                return None
        except Exception:
            return None

        x = ctypes.c_short(int(lparam) & 0xFFFF).value
        y = ctypes.c_short((int(lparam) >> 16) & 0xFFFF).value

        try:
            dpi = ctypes.windll.user32.GetDpiForWindow(wintypes.HWND(hwnd))
            scale = max(1.0, float(dpi) / 96.0)
        except Exception:
            scale = 1.0
        border = max(5, int(round(6 * scale)))

        if not self._controller._is_maximized_or_fullscreen(win):
            left = x < rect.left + border
            right = x >= rect.right - border
            top = y < rect.top + border
            bottom = y >= rect.bottom - border

            if top and left:
                return self.HTTOPLEFT
            if top and right:
                return self.HTTOPRIGHT
            if bottom and left:
                return self.HTBOTTOMLEFT
            if bottom and right:
                return self.HTBOTTOMRIGHT
            if left:
                return self.HTLEFT
            if right:
                return self.HTRIGHT
            if top:
                return self.HTTOP
            if bottom:
                return self.HTBOTTOM
        local_x = (x - rect.left) / scale
        local_y = (y - rect.top) / scale
        if self._caption_hit_test(win, local_x, local_y):
            return HTCAPTION
        return None

    def _caption_hit_test(self, win: QWindow, local_x: float, local_y: float) -> bool:
        if self._controller._visibility_name(win) == "fullscreen":
            return False
        try:
            height = int(win.property("nativeTitleBarHeight") or 36)
        except Exception:
            height = 36
        height = max(24, min(80, height))
        if local_y < 0 or local_y > float(height):
            return False
        regions: list[tuple[int, int]] = []
        for left_name, right_name in (("nativeCaptionLeftA", "nativeCaptionRightA"), ("nativeCaptionLeftB", "nativeCaptionRightB")):
            try:
                left = int(win.property(left_name) or 0)
                right = int(win.property(right_name) or 0)
            except Exception:
                continue
            if right > left + 2:
                regions.append((left, right))
        if regions:
            return any(float(left) <= local_x <= float(right) for left, right in regions)
        try:
            return 0 <= local_x <= max(0, int(win.width()) - 150)
        except Exception:
            return False


class WindowController(QObject):
    snapPreviewChanged = Signal(str, int, int, int, int, bool)
    nativeResizeChanged = Signal()
    snappedVisualChanged = Signal(str, bool)
    captionPressed = Signal(str)

    def __init__(self, settings, parent=None):
        super().__init__(parent)
        self._settings = settings
        self._normal_geometries: dict[str, QRect] = {}
        self._normal_frame_geometries: dict[str, QRect] = {}
        self._drag_restore_geometries: dict[str, QRect] = {}
        self._move_states: dict[int, dict] = {}
        self._resize_states: dict[int, dict] = {}
        self._snap_rects: dict[int, QRect] = {}
        self._snap_types: dict[int, str] = {}
        self._snapped_normal_geometries: dict[str, QRect] = {}
        self._snapped_rects_by_key: dict[str, QRect] = {}
        self._snap_margin = 14
        self._native_frame_windows: set[int] = set()
        self._chrome_refresh_pending: set[int] = set()
        self._hwnd_to_window: dict[int, QWindow] = {}
        self._move_stabilize_tokens: dict[int, int] = {}

        self._session_timer = QTimer(self)
        # Keep this timer only as a release watchdog.  Moving the window from
        # both QML mouse events and this timer can produce a delayed one-frame
        # position correction after fast release, which feels like inertia/drift.
        self._session_timer.setInterval(12)
        self._session_timer.timeout.connect(self._tick_sessions)

        self._native_filter = _WindowsHitTestFilter(self) if sys.platform == "win32" else None
        if self._native_filter is not None:
            try:
                app = QGuiApplication.instance()
                if app is not None:
                    app.installNativeEventFilter(self._native_filter)
                else:
                    self._native_filter = None
            except Exception:
                self._native_filter = None

    @Slot()
    def shutdown(self) -> None:
        if self._session_timer.isActive():
            self._session_timer.stop()
        self._move_states.clear()
        self._resize_states.clear()
        self._snap_rects.clear()
        self._snap_types.clear()
        if self._native_filter is not None:
            try:
                app = QGuiApplication.instance()
                if app is not None:
                    app.removeNativeEventFilter(self._native_filter)
            except Exception:
                pass
            self._native_filter = None

    @Property(bool, notify=nativeResizeChanged)
    def nativeResize(self) -> bool:
        # Windows gets native WM_NCHITTEST resizing.  Other platforms keep the
        # QML ResizeArea + startSystemResize/manual fallback path.
        return sys.platform == "win32" and self._native_filter is not None

    @Slot(QObject)
    def installNativeFrame(self, win: QWindow) -> None:
        if win is None:
            return
        self._native_frame_windows.add(id(win))
        QTimer.singleShot(0, lambda win=win: self._apply_native_frame(win))
        QTimer.singleShot(100, lambda win=win: self._apply_native_frame(win))

    @Slot(QObject)
    def refreshNativeFrame(self, win: QWindow) -> None:
        if win is None or id(win) not in self._native_frame_windows:
            return
        # Apply immediately.  Delayed DWM refreshes can make the shadow look as
        # if it lags behind during fast resize/move interactions.
        self._apply_native_frame(win)

    def _flush_chrome_refresh(self, win: QWindow, wid: int) -> None:
        self._chrome_refresh_pending.discard(wid)
        self._apply_native_frame(win)

    @Slot(QObject)
    def activateWindow(self, win: QWindow) -> None:
        if win is not None:
            self._raise_window(win)

    @Slot(QObject)
    def rememberNormalGeometry(self, win: QWindow) -> None:
        if win is None or self._is_maximized_or_fullscreen(win):
            return
        key = self._key(win)
        geom = self._coalesced_normal_geometry(key, QRect(win.geometry()))
        self._normal_geometries[key] = QRect(geom)
        self._remember_frame_geometry(key, win, geom)

    @Slot(QObject)
    def toggleMaximized(self, win: QWindow) -> None:
        if win is None:
            return
        key = self._key(win)
        if self._visibility_name(win) in {"maximized", "fullscreen"}:
            self._clear_snapped_state(key)
            if sys.platform == "win32" and self._send_windows_maximize_command(win, restore=True):
                pass
            else:
                win.showNormal()
                geom = self._normal_geometries.get(key)
                if geom is not None and geom.width() >= 320 and geom.height() >= 240:
                    QTimer.singleShot(0, lambda win=win, geom=QRect(geom): self._safe_set_geometry(win, geom))
            self.refreshNativeFrame(win)
            return
        self._clear_snapped_state(key)
        self.rememberNormalGeometry(win)
        if not (sys.platform == "win32" and self._send_windows_maximize_command(win, restore=False)):
            win.showMaximized()
        self._settings.set_value_py(f"windows/{key}/visibility", "maximized")
        self.refreshNativeFrame(win)

    @Slot(QObject, result=bool)
    def isMaximizedState(self, win: QWindow) -> bool:
        if win is None:
            return False
        return self._is_maximized_or_fullscreen(win)

    @Slot(QObject, float, float)
    def beginMove(self, win: QWindow, local_x: float, local_y: float) -> None:
        if win is None:
            return
        self._raise_window(win)
        key = self._key(win)
        wid = id(win)
        self._hide_snap_preview(key, wid)
        start_visibility = self._visibility_name(win)
        if start_visibility == "fullscreen":
            return
        pos = QCursor.pos()
        snapped_normal = self._snapped_normal_geometries.get(key)
        snapped_rect = self._snapped_rects_by_key.get(key)
        saved_visibility = str(self._settings.value_py(f"windows/{key}/visibility", "normal"))
        looks_snapped = self._looks_like_snapped_window(win, key)
        if start_visibility == "normal" and (
            (snapped_normal is not None and (self._geometry_matches(win.geometry(), snapped_rect, tolerance=180) or looks_snapped))
            or saved_visibility.startswith("snapped-")
        ):
            start_visibility = "snapped"
            candidate = QRect(snapped_normal) if snapped_normal is not None else self._load_normal_geometry(key, win)
            normal_at_start = self._repair_normal_geometry_for_unsnap(win, key, candidate)
        elif start_visibility == "normal":
            normal_at_start = QRect(win.geometry())
            self._normal_geometries[key] = QRect(normal_at_start)
            self._remember_frame_geometry(key, win, normal_at_start)
            self._clear_snapped_state(key)
        else:
            normal_at_start = self._normal_geometries.get(key) or self._load_normal_geometry(key, win)

        if sys.platform == "win32":
            if self._begin_windows_native_caption_move(win, key, local_x, local_y, start_visibility, normal_at_start):
                return
            if start_visibility != "normal":
                self._begin_windows_manual_restore_move(win, key, local_x, local_y, start_visibility, normal_at_start)
                return

        self._move_states[wid] = {
            "win": win,
            "key": key,
            "local_x": float(local_x),
            "local_y": float(local_y),
            "start_pos_x": pos.x(),
            "start_pos_y": pos.y(),
            "last_x": win.x(),
            "last_y": win.y(),
            "dragging": False,
            "restored": start_visibility == "normal",
            "start_visibility": start_visibility,
            "start_width": max(1, win.width()),
            "normal_geometry": QRect(normal_at_start),
        }
        self._ensure_session_timer()

    def _begin_windows_manual_restore_move(self, win: QWindow, key: str, local_x: float, local_y: float, start_visibility: str, normal_at_start: QRect) -> None:
        if not self._is_valid_window(win):
            return
        pos = QCursor.pos()
        normal = QRect(normal_at_start)
        full_width = max(1, int(win.width()))
        full_height = max(1, int(win.height()))
        ratio_x = max(0.0, min(1.0, float(local_x) / float(full_width)))
        anchor_y = max(6.0, min(float(local_y), min(42.0, full_height * 0.20)))
        new_x = int(pos.x() - normal.width() * ratio_x)
        new_y = int(pos.y() - anchor_y)
        target = QRect(new_x, new_y, normal.width(), normal.height())
        try:
            if sys.platform == "win32":
                hwnd = wintypes.HWND(int(win.winId()))
                self._set_windows_restore_bounds(win, key, target, hwnd, normal)
                # Keep Qt's cached normal geometry in sync with the native
                # restore bounds before showNormal(). Without this, maximized
                # QML windows can paint the previous normal size for one frame
                # and then jump to the drag target.
                win.setGeometry(target)
                self._set_windows_restore_bounds(win, key, target, hwnd, target)
            win.showNormal()
            if not self._geometry_matches(win.geometry(), target, tolerance=1):
                win.setGeometry(target)
        except Exception:
            return
        self._clear_snapped_state(key)
        self._normal_geometries[key] = QRect(target)
        self._drag_restore_geometries[key] = QRect(target)
        self._settings.set_value_py(f"windows/{key}/visibility", "normal")
        self._move_states[id(win)] = {
            "win": win,
            "key": key,
            "local_x": float(pos.x() - new_x),
            "local_y": float(pos.y() - new_y),
            "start_pos_x": pos.x(),
            "start_pos_y": pos.y(),
            "last_x": new_x,
            "last_y": new_y,
            "dragging": True,
            "restored": True,
            "start_visibility": start_visibility,
            "start_width": max(1, normal.width()),
            "normal_geometry": QRect(normal),
            "restored_size": (int(normal.width()), int(normal.height())),
        }
        self._remember_frame_geometry(key, win, self._normal_geometries[key])
        self._ensure_session_timer()
        self.refreshNativeFrame(win)

    def _begin_windows_native_caption_move(self, win: QWindow, key: str, local_x: float, local_y: float, start_visibility: str, normal_at_start: QRect) -> bool:
        if sys.platform != "win32" or not self._is_valid_window(win):
            return False
        try:
            hwnd_value = int(win.winId())
        except Exception:
            return False
        if not hwnd_value:
            return False

        normal = QRect(normal_at_start)
        if normal.width() < 320 or normal.height() < 240:
            normal = self._load_normal_geometry(key, win)
        if normal.width() < 320 or normal.height() < 240:
            return False

        restore_geometry = QRect(normal)
        try:
            if start_visibility != "normal":
                restore_geometry = self._restore_drag_target_for_window(win, normal, local_x, local_y)
                self._set_windows_restore_bounds(win, key, restore_geometry, wintypes.HWND(hwnd_value), normal)
                self._drag_restore_geometries[key] = QRect(restore_geometry)
                self._normal_geometries[key] = QRect(restore_geometry)
                self._clear_snapped_state(key)
                self._settings.set_value_py(f"windows/{key}/visibility", "normal")
            else:
                self._normal_geometries[key] = self._coalesced_normal_geometry(key, QRect(win.geometry()))
                self._remember_frame_geometry(key, win, self._normal_geometries[key])

            self._move_states[id(win)] = {
                "win": win,
                "key": key,
                "system_move": True,
                "dragging": True,
                "normal_geometry": QRect(restore_geometry),
                "start_visibility": start_visibility,
            }
            self._ensure_session_timer()
            ctypes.windll.user32.ReleaseCapture()
            ctypes.windll.user32.SendMessageW(wintypes.HWND(hwnd_value), WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0)
            if id(win) in self._move_states and not bool(QGuiApplication.mouseButtons() & Qt.MouseButton.LeftButton):
                self._finish_move(win)
            return True
        except Exception:
            self._move_states.pop(id(win), None)
            self._hide_snap_preview(key, id(win))
            self._stop_session_timer_if_idle()
            return False

    def _begin_system_move(self, win: QWindow, key: str, local_x: float, local_y: float, start_visibility: str, normal_at_start: QRect) -> bool:
        if not self._is_valid_window(win):
            return False
        pos = QCursor.pos()
        try:
            normal = QRect(normal_at_start)
            # Restore maximized or snapped windows before entering the native
            # move loop. Recompute the mouse anchor after setting geometry so
            # the restored window does not jump under the cursor.
            if start_visibility != "normal":
                full_width = max(1, win.width())
                ratio_x = max(0.0, min(1.0, float(local_x) / float(full_width)))
                new_x = int(pos.x() - normal.width() * ratio_x)
                new_y = int(pos.y() - min(float(local_y), 38.0))
                win.showNormal()
                win.setGeometry(new_x, new_y, normal.width(), normal.height())
                self._clear_snapped_state(key)
                self._normal_geometries[key] = QRect(normal)
                self._settings.set_value_py(f"windows/{key}/visibility", "normal")
            else:
                self._normal_geometries[key] = self._coalesced_normal_geometry(key, QRect(win.geometry()))

            started = False
            try:
                if hasattr(win, "startSystemMove"):
                    started = bool(win.startSystemMove())
            except Exception:
                started = False
            if not started:
                return False

            wid = id(win)
            self._move_states[wid] = {
                "win": win,
                "key": key,
                "system_move": True,
                "dragging": True,
                "normal_geometry": QRect(normal),
                "start_visibility": start_visibility,
            }
            self._ensure_session_timer()
            return True
        except Exception:
            return False

    @Slot(QObject)
    def updateMove(self, win: QWindow) -> None:
        if win is None:
            return
        state = self._move_states.get(id(win))
        if not state:
            return
        if bool(state.get("system_move", False)):
            return
        pos = QCursor.pos()
        moved = abs(pos.x() - int(state["start_pos_x"])) + abs(pos.y() - int(state["start_pos_y"]))
        if not bool(state.get("dragging")) and moved < 4:
            return
        state["dragging"] = True
        if not bool(state.get("restored", False)):
            self._restore_for_drag(win, state, pos.x(), pos.y())
            return
        new_x = int(pos.x() - float(state["local_x"]))
        new_y = int(pos.y() - float(state["local_y"]))
        if new_x != int(state.get("last_x", win.x())) or new_y != int(state.get("last_y", win.y())):
            try:
                win.setPosition(new_x, new_y)
            except Exception:
                try:
                    win.setGeometry(QRect(new_x, new_y, win.width(), win.height()))
                except Exception:
                    return
            state["last_x"] = new_x
            state["last_y"] = new_y
        self._update_move_snap_preview(win, state, pos)

    @Slot(QObject)
    def endMove(self, win: QWindow) -> None:
        if win is None:
            return
        self._finish_move(win)
        self._stop_session_timer_if_idle()

    @Slot(QObject, int)
    def beginResize(self, win: QWindow, edge_value: int) -> None:
        if win is None or self._is_maximized_or_fullscreen(win):
            return
        self._raise_window(win)
        self.rememberNormalGeometry(win)
        started = False
        try:
            if hasattr(win, "startSystemResize"):
                started = bool(win.startSystemResize(Qt.Edges(int(edge_value))))
        except Exception:
            started = False
        if started:
            # Native resize owns the drag session.  Do not also run the manual
            # timer, otherwise the QML scene can appear to resize independently
            # from the actual top-level window frame.
            return
        self._begin_manual_resize(win, int(edge_value))

    @Slot(QObject)
    def updateResize(self, win: QWindow) -> None:
        # Manual fallback path for platforms where startSystemResize() is not
        # available. On Windows, native WM_NCHITTEST is used and ResizeArea is
        # disabled, so this method normally becomes a no-op.
        if win is not None:
            self._apply_resize_state(win)

    @Slot(QObject)
    def endResize(self, win: QWindow) -> None:
        if win is not None:
            if id(win) in self._resize_states:
                self._finish_resize(win)
            elif not self._is_maximized_or_fullscreen(win):
                key = self._key(win)
                self._normal_geometries[key] = QRect(win.geometry())
                self._remember_frame_geometry(key, win, self._normal_geometries[key])
                self._settings.set_value_py(f"windows/{key}/normalGeometry", {"x": win.x(), "y": win.y(), "w": win.width(), "h": win.height()})
                self._settings.set_value_py(f"windows/{key}/visibility", "normal")
                self.refreshNativeFrame(win)
            self._stop_session_timer_if_idle()

    @Slot(QObject)
    def restoreWindowState(self, win: QWindow) -> None:
        if win is None:
            return
        key = self._key(win)
        saved = self._settings.value_py(f"windows/{key}/normalGeometry", None)
        if isinstance(saved, dict):
            try:
                geom = QRect(int(saved["x"]), int(saved["y"]), int(saved["w"]), int(saved["h"]))
                if geom.width() >= 320 and geom.height() >= 240:
                    win.setGeometry(geom)
                    self._normal_geometries[key] = QRect(geom)
                    self._normal_frame_geometries[key] = QRect(geom)
            except Exception:
                pass
        visibility = self._settings.value_py(f"windows/{key}/visibility", "normal")
        always_on_top = bool(self._settings.value_py(f"windows/{key}/alwaysOnTop", False))
        if always_on_top:
            self.setAlwaysOnTop(win, True)
        if visibility == "maximized":
            QTimer.singleShot(0, lambda win=win: self._safe_window_call(win, "showMaximized"))
        elif visibility == "fullscreen":
            QTimer.singleShot(0, lambda win=win: self._safe_window_call(win, "showFullScreen"))
        else:
            QTimer.singleShot(0, lambda win=win: self._safe_window_call(win, "showNormal"))
        QTimer.singleShot(120, lambda win=win: self._apply_native_frame(win))

    @Slot(QObject)
    def saveWindowState(self, win: QWindow) -> None:
        if win is None:
            return
        key = self._key(win)
        visibility = self._visibility_name(win)
        if not self._is_maximized_or_fullscreen(win):
            if self._actual_geometry_looks_snapped(win):
                candidate = self._normal_geometries.get(key) or self._load_normal_geometry(key, win)
                geometry = self._repair_normal_geometry_for_unsnap(win, key, QRect(candidate))
                self._normal_geometries[key] = QRect(geometry)
                self._snapped_normal_geometries[key] = QRect(geometry)
                self._snapped_rects_by_key[key] = QRect(win.geometry())
                visibility = f"snapped-{self._snapped_side(win)}"
            elif key in self._snapped_normal_geometries and self._geometry_matches(win.geometry(), self._snapped_rects_by_key.get(key)):
                geometry = QRect(self._snapped_normal_geometries[key])
                visibility = str(self._settings.value_py(f"windows/{key}/visibility", "normal"))
            elif key in self._drag_restore_geometries:
                geometry = QRect(self._drag_restore_geometries[key])
                self._normal_geometries[key] = QRect(geometry)
                self._remember_frame_geometry(key, win, geometry)
                visibility = "normal"
            else:
                geometry = self._coalesced_normal_geometry(key, QRect(win.geometry()))
                self._normal_geometries[key] = QRect(geometry)
                self._remember_frame_geometry(key, win, geometry)
                self._clear_snapped_state(key)
                visibility = "normal"
        else:
            geometry = self._normal_geometries.get(key, win.geometry())
        self._settings.set_value_py(f"windows/{key}/normalGeometry", {"x": geometry.x(), "y": geometry.y(), "w": geometry.width(), "h": geometry.height()})
        self._settings.set_value_py(f"windows/{key}/visibility", visibility)

    @Slot(QObject, bool)
    def setAlwaysOnTop(self, win: QWindow, enabled: bool) -> None:
        if win is None:
            return
        flags = win.flags()
        if sys.platform == "win32" and self._is_valid_window(win):
            try:
                user32 = ctypes.windll.user32
                HWND_TOPMOST = -1
                HWND_NOTOPMOST = -2
                SWP_NOMOVE = 0x0002
                SWP_NOSIZE = 0x0001
                SWP_NOACTIVATE = 0x0010
                SWP_NOOWNERZORDER = 0x0200
                user32.SetWindowPos(wintypes.HWND(int(win.winId())), HWND_TOPMOST if enabled else HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER)
            except Exception:
                pass
        else:
            if enabled:
                flags |= Qt.WindowType.WindowStaysOnTopHint
            else:
                flags &= ~Qt.WindowType.WindowStaysOnTopHint
            win.setFlags(flags)
        try:
            win.setProperty("alwaysOnTop", bool(enabled))
        except Exception:
            pass
        key = self._key(win)
        self._settings.set_value_py(f"windows/{key}/alwaysOnTop", bool(enabled))
        if not (sys.platform == "win32" and self._is_valid_window(win)):
            win.show()
            self._raise_window(win)
        self.refreshNativeFrame(win)

    @Slot(str, str, "QVariant")
    def handleWindowEvent(self, window_key: str, event_type: str, payload) -> None:
        _ = (window_key, event_type, payload)

    def _ensure_session_timer(self) -> None:
        if not self._session_timer.isActive():
            self._session_timer.start()

    def _stop_session_timer_if_idle(self) -> None:
        if not self._move_states and not self._resize_states and self._session_timer.isActive():
            self._session_timer.stop()

    def _tick_sessions(self) -> None:
        if not self._move_states and not self._resize_states:
            self._stop_session_timer_if_idle()
            return
        left_down = bool(QGuiApplication.mouseButtons() & Qt.MouseButton.LeftButton)
        move_wins = [state.get("win") for state in list(self._move_states.values())]
        resize_wins = [state.get("win") for state in list(self._resize_states.values())]
        if not left_down:
            for win in move_wins:
                if win is not None:
                    self._finish_move(win)
            for win in resize_wins:
                if win is not None:
                    self._finish_resize(win)
            self._stop_session_timer_if_idle()
            return
        # Do not keep moving windows from the watchdog timer.  QML MouseArea
        # position events are the single source of truth while dragging.  The
        # timer only refreshes the snap preview at blocked screen edges and
        # detects releases that happen outside the title bar.
        pos = QCursor.pos()
        for state in list(self._move_states.values()):
            win = state.get("win")
            if win is not None and self._is_valid_window(win) and bool(state.get("dragging", False)) and not bool(state.get("system_move", False)):
                self._update_move_snap_preview(win, state, pos)
        for win in resize_wins:
            if win is not None:
                self._apply_resize_state(win)

    def _begin_manual_resize(self, win: QWindow, edge_value: int) -> None:
        if not self._is_valid_window(win):
            return
        pos = QCursor.pos()
        geom = QRect(win.geometry())
        self._resize_states[id(win)] = {
            "win": win,
            "key": self._key(win),
            "edges": int(edge_value),
            "start_x": pos.x(),
            "start_y": pos.y(),
            "start_geom": QRect(geom),
            "last_geom": QRect(geom),
        }
        self._ensure_session_timer()

    def _apply_resize_state(self, win: QWindow) -> None:
        state = self._resize_states.get(id(win))
        if not state or not self._is_valid_window(win):
            return
        geom = QRect(state["start_geom"])
        pos = QCursor.pos()
        dx = pos.x() - int(state["start_x"])
        dy = pos.y() - int(state["start_y"])
        edges = int(state["edges"])
        left = bool(edges & self._edge_value(Qt.Edge.LeftEdge))
        right = bool(edges & self._edge_value(Qt.Edge.RightEdge))
        top = bool(edges & self._edge_value(Qt.Edge.TopEdge))
        bottom = bool(edges & self._edge_value(Qt.Edge.BottomEdge))
        min_w, min_h = self._minimum_size(win)
        x, y, w, h = geom.x(), geom.y(), geom.width(), geom.height()
        if left:
            nx = x + dx
            nw = w - dx
            if nw < min_w:
                nx = x + w - min_w
                nw = min_w
            x, w = nx, nw
        if right:
            w = max(min_w, w + dx)
        if top:
            ny = y + dy
            nh = h - dy
            if nh < min_h:
                ny = y + h - min_h
                nh = min_h
            y, h = ny, nh
        if bottom:
            h = max(min_h, h + dy)
        new_geom = QRect(int(x), int(y), int(w), int(h))
        if QRect(state.get("last_geom", QRect())) == new_geom:
            return
        try:
            win.setGeometry(new_geom)
            state["last_geom"] = QRect(new_geom)
        except Exception:
            pass

    def _finish_resize(self, win: QWindow) -> None:
        state = self._resize_states.pop(id(win), None)
        if state is None or not self._is_valid_window(win):
            return
        key = str(state.get("key") or self._key(win))
        if not self._is_maximized_or_fullscreen(win):
            self._normal_geometries[key] = QRect(win.geometry())
            self._remember_frame_geometry(key, win, self._normal_geometries[key])
            self._settings.set_value_py(f"windows/{key}/normalGeometry", {"x": win.x(), "y": win.y(), "w": win.width(), "h": win.height()})
            self._settings.set_value_py(f"windows/{key}/visibility", "normal")
        self.refreshNativeFrame(win)

    def _finish_move(self, win: QWindow) -> None:
        wid = id(win)
        state = self._move_states.pop(wid, None)
        key = self._key(win) if state is None else str(state["key"])
        snap_rect = self._snap_rects.pop(wid, None)
        snap_type = self._snap_types.pop(wid, None)
        self.snapPreviewChanged.emit(key, 0, 0, 0, 0, False)
        if state is None:
            return
        if bool(state.get("system_move", False)):
            self._finish_system_move(win, key, state)
            return
        if snap_rect is not None and bool(state.get("dragging", False)):
            normal = QRect(state["normal_geometry"])
            if normal.width() >= 320 and normal.height() >= 240:
                self._normal_geometries[key] = QRect(normal)
            try:
                win.showNormal()
                win.setGeometry(QRect(snap_rect))
            except Exception:
                pass
            if snap_type == "top":
                self._clear_snapped_state(key)
                win.showMaximized()
                QTimer.singleShot(0, lambda win=win: self._safe_window_call(win, "showMaximized"))
                self._settings.set_value_py(f"windows/{key}/visibility", "maximized")
            else:
                self._snapped_normal_geometries[key] = QRect(normal)
                self._snapped_rects_by_key[key] = QRect(win.geometry())
                self._settings.set_value_py(f"windows/{key}/visibility", f"snapped-{snap_type}")
                self.snappedVisualChanged.emit(key, True)
                QTimer.singleShot(80, lambda win=win, key=key: self._remember_actual_snapped_rect(win, key))
            QTimer.singleShot(100, lambda win=win: self._apply_native_frame(win))
            return
        if bool(state.get("dragging", False)) and not self._is_maximized_or_fullscreen(win):
            self._clear_snapped_state(key)
            self._drag_restore_geometries.pop(key, None)
            # Do not perform a final cursor-based setPosition here.  Fast drag
            # release can deliver one stale global cursor sample after the last
            # QML move event; applying it is exactly the visible delayed drift.
            # The last geometry already applied by updateMove() is authoritative.
            final_geom = self._coalesced_normal_geometry(key, QRect(win.geometry()))
            self._normal_geometries[key] = QRect(final_geom)
            self._settings.set_value_py(f"windows/{key}/visibility", "normal")


    def _finish_system_move(self, win: QWindow, key: str, state: dict) -> None:
        if not self._is_valid_window(win):
            return
        # Defer one lightweight read so Windows has finished applying a native
        # snap/maximize result. We only record state; we do not set geometry.
        QTimer.singleShot(80, lambda win=win, key=key, state=dict(state): self._record_after_system_move(win, key, state))

    def _record_after_system_move(self, win: QWindow, key: str, state: dict) -> None:
        if not self._is_valid_window(win):
            return
        visibility = self._visibility_name(win)
        restored = self._drag_restore_geometries.pop(key, None)
        if visibility in {"maximized", "fullscreen"}:
            normal = QRect(state.get("normal_geometry", restored or self._normal_geometries.get(key, win.geometry())))
            if normal.width() >= 320 and normal.height() >= 240:
                self._normal_geometries[key] = QRect(normal)
                self._settings.set_value_py(f"windows/{key}/normalGeometry", {"x": normal.x(), "y": normal.y(), "w": normal.width(), "h": normal.height()})
            self._settings.set_value_py(f"windows/{key}/visibility", visibility)
            return
        if self._looks_like_snapped_window(win, key):
            normal = QRect(state.get("normal_geometry", restored or self._normal_geometries.get(key, win.geometry())))
            if normal.width() >= 320 and normal.height() >= 240:
                self._snapped_normal_geometries[key] = QRect(normal)
                self._normal_geometries[key] = QRect(normal)
                self._settings.set_value_py(f"windows/{key}/normalGeometry", {"x": normal.x(), "y": normal.y(), "w": normal.width(), "h": normal.height()})
            self._snapped_rects_by_key[key] = QRect(win.geometry())
            self.snappedVisualChanged.emit(key, True)
            side = "left"
            try:
                screen = win.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
                area = screen.availableGeometry() if screen is not None else None
                if area is not None and abs(win.geometry().right() - area.right()) <= 12:
                    side = "right"
            except Exception:
                pass
            self._settings.set_value_py(f"windows/{key}/visibility", f"snapped-{side}")
            return
        self._clear_snapped_state(key)
        if restored is not None:
            current = QRect(win.geometry())
            geom = QRect(current.x(), current.y(), restored.width(), restored.height())
        else:
            geom = self._coalesced_normal_geometry(key, QRect(win.geometry()))
        self._normal_geometries[key] = QRect(geom)
        self._remember_frame_geometry(key, win, geom)
        self._settings.set_value_py(f"windows/{key}/normalGeometry", {"x": geom.x(), "y": geom.y(), "w": geom.width(), "h": geom.height()})
        self._settings.set_value_py(f"windows/{key}/visibility", "normal")

    def _set_windows_restore_bounds(self, win: QWindow, key: str, client_geom: QRect, hwnd, reference_client: QRect | None = None) -> QRect:
        user32 = ctypes.windll.user32
        outer = self._frame_geometry_for_client(key, client_geom, reference_client, hwnd)

        try:
            class WINDOWPLACEMENT(ctypes.Structure):
                _fields_ = [
                    ("length", wintypes.UINT),
                    ("flags", wintypes.UINT),
                    ("showCmd", wintypes.UINT),
                    ("ptMinPosition", wintypes.POINT),
                    ("ptMaxPosition", wintypes.POINT),
                    ("rcNormalPosition", wintypes.RECT),
                ]

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
        return outer

    def _current_frame_geometry(self, win: QWindow) -> QRect:
        if sys.platform == "win32" and self._is_valid_window(win):
            try:
                rect = wintypes.RECT()
                hwnd = wintypes.HWND(int(win.winId()))
                if ctypes.windll.user32.GetWindowRect(hwnd, ctypes.byref(rect)):
                    return QRect(
                        int(rect.left),
                        int(rect.top),
                        int(rect.right - rect.left),
                        int(rect.bottom - rect.top),
                    )
            except Exception:
                pass
        try:
            frame = win.frameGeometry()
            if frame.isValid():
                return QRect(frame)
        except Exception:
            pass
        try:
            return QRect(win.geometry())
        except Exception:
            return QRect()

    def _remember_frame_geometry(self, key: str, win: QWindow, client_geom: QRect) -> None:
        frame = self._current_frame_geometry(win)
        if not frame.isValid() or not client_geom.isValid():
            return
        try:
            dw = int(frame.width()) - int(client_geom.width())
            dh = int(frame.height()) - int(client_geom.height())
            if 0 <= dw <= 128 and 0 <= dh <= 128:
                self._normal_frame_geometries[str(key)] = QRect(frame)
        except Exception:
            pass

    def _frame_geometry_for_client(self, key: str, client_geom: QRect, reference_client: QRect | None = None, hwnd=None) -> QRect:
        if sys.platform == "win32" and hwnd is not None:
            try:
                return self._native_outer_rect_for_client(hwnd, client_geom)
            except Exception:
                pass
        key = str(key)
        reference = QRect(reference_client) if reference_client is not None else self._normal_geometries.get(key)
        frame = self._normal_frame_geometries.get(key)
        if frame is not None and reference is not None and frame.isValid() and reference.isValid():
            try:
                dx = int(frame.x()) - int(reference.x())
                dy = int(frame.y()) - int(reference.y())
                dw = int(frame.width()) - int(reference.width())
                dh = int(frame.height()) - int(reference.height())
                if abs(dx) <= 96 and abs(dy) <= 96 and 0 <= dw <= 128 and 0 <= dh <= 128:
                    return QRect(
                        int(client_geom.x()) + dx,
                        int(client_geom.y()) + dy,
                        int(client_geom.width()) + dw,
                        int(client_geom.height()) + dh,
                    )
            except Exception:
                pass
        return QRect(client_geom)

    def _native_outer_rect_for_client(self, hwnd, client_geom: QRect) -> QRect:
        # The native event filter returns 0 for WM_NCCALCSIZE, so our visible
        # QML bounds are already the HWND bounds. AdjustWindowRectEx would add
        # an invisible frame that Windows later subtracts, causing repeated
        # maximize/snap drag-restores to shrink by a few pixels each time.
        return QRect(client_geom)

    def _restore_for_drag(self, win: QWindow, state: dict, cursor_x: int, cursor_y: int) -> None:
        normal = QRect(state["normal_geometry"])
        full_width = max(1, int(state.get("start_width", win.width())))
        ratio_x = max(0.0, min(1.0, float(state["local_x"]) / full_width))
        new_x = int(cursor_x - normal.width() * ratio_x)
        new_y = int(cursor_y - min(float(state["local_y"]), 38.0))
        try:
            win.showNormal()
            win.setGeometry(new_x, new_y, normal.width(), normal.height())
        except Exception:
            return
        state["restored"] = True
        self._clear_snapped_state(str(state.get("key") or self._key(win)))
        self._remember_frame_geometry(str(state.get("key") or self._key(win)), win, normal)
        state["local_x"] = float(cursor_x - new_x)
        state["local_y"] = float(cursor_y - new_y)
        state["last_x"] = new_x
        state["last_y"] = new_y
        self._raise_window(win)
        self.refreshNativeFrame(win)

    def _restore_drag_target_for_window(self, win: QWindow, normal: QRect, local_x: float, local_y: float) -> QRect:
        pos = QCursor.pos()
        full_width = max(1, int(win.width()))
        full_height = max(1, int(win.height()))
        ratio_x = max(0.0, min(1.0, float(local_x) / float(full_width)))
        anchor_y = max(6.0, min(float(local_y), min(42.0, full_height * 0.20)))
        return QRect(
            int(pos.x() - normal.width() * ratio_x),
            int(pos.y() - anchor_y),
            int(normal.width()),
            int(normal.height()),
        )

    def _stabilize_after_move(self, win: QWindow, geom: QRect) -> None:
        # Disabled: delayed post-release setPosition can look like inertial drift.
        return

    def _snap_target_for_cursor(self, win: QWindow, cursor_x: int, cursor_y: int) -> tuple[QRect, str] | None:
        screen = win.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
        if screen is None:
            return None
        area = screen.availableGeometry()
        if cursor_y <= area.top() + self._snap_margin:
            return QRect(area), "top"
        min_w, _ = self._minimum_size(win)
        half_w = max(min_w, area.width() // 2)
        half_w = min(half_w, area.width())
        if cursor_x <= area.left() + self._snap_margin:
            return QRect(area.left(), area.top(), half_w, area.height()), "left"
        if cursor_x >= area.right() - self._snap_margin:
            return QRect(area.right() - half_w + 1, area.top(), half_w, area.height()), "right"
        return None

    def _update_move_snap_preview(self, win: QWindow, state: dict, pos=None) -> None:
        if not self._is_valid_window(win):
            return
        if pos is None:
            pos = QCursor.pos()
        key = str(state.get("key") or self._key(win))
        wid = id(win)
        target = self._snap_target_for_cursor(win, int(pos.x()), int(pos.y()))
        if target is not None:
            snap_rect, snap_type = target
            old = self._snap_rects.get(wid)
            self._snap_rects[wid] = QRect(snap_rect)
            self._snap_types[wid] = snap_type
            if old is None or old != snap_rect:
                self.snapPreviewChanged.emit(key, snap_rect.x(), snap_rect.y(), snap_rect.width(), snap_rect.height(), True)
        else:
            self._hide_snap_preview(key, wid)

    def _hide_snap_preview(self, key: str, wid: int) -> None:
        if wid in self._snap_rects:
            self._snap_rects.pop(wid, None)
            self._snap_types.pop(wid, None)
            self.snapPreviewChanged.emit(key, 0, 0, 0, 0, False)

    def _clear_snapped_state(self, key: str) -> None:
        key = str(key)
        had = key in self._snapped_normal_geometries or key in self._snapped_rects_by_key
        self._snapped_normal_geometries.pop(key, None)
        self._snapped_rects_by_key.pop(key, None)
        if had:
            self.snappedVisualChanged.emit(key, False)


    def _remember_actual_snapped_rect(self, win: QWindow, key: str) -> None:
        if self._is_valid_window(win) and str(self._settings.value_py(f"windows/{key}/visibility", "")).startswith("snapped-"):
            self._snapped_rects_by_key[str(key)] = QRect(win.geometry())

    def _looks_like_snapped_window(self, win: QWindow, key: str) -> bool:
        try:
            saved_visibility = str(self._settings.value_py(f"windows/{key}/visibility", "normal"))
            if saved_visibility.startswith("snapped-"):
                return True
            return self._actual_geometry_looks_snapped(win)
        except Exception:
            return False

    def _actual_geometry_looks_snapped(self, win: QWindow) -> bool:
        try:
            screen = win.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
            if screen is None:
                return False
            area = screen.availableGeometry()
            geom = win.geometry()
            edge_aligned = abs(geom.x() - area.left()) <= 8 or abs(geom.right() - area.right()) <= 8
            tall = abs(geom.y() - area.top()) <= 8 and abs(geom.height() - area.height()) <= 16
            not_full = geom.width() < area.width() - 80
            return bool(edge_aligned and tall and not_full)
        except Exception:
            return False

    def _snapped_side(self, win: QWindow) -> str:
        try:
            screen = win.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
            area = screen.availableGeometry() if screen is not None else None
            if area is not None and abs(win.geometry().right() - area.right()) <= 12:
                return "right"
        except Exception:
            pass
        return "left"

    def _repair_normal_geometry_for_unsnap(self, win: QWindow, key: str, candidate: QRect) -> QRect:
        try:
            screen = win.screen() or QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
            area = screen.availableGeometry() if screen is not None else None
            geom = win.geometry()
            min_w, min_h = self._minimum_size(win)
            # If an older version accidentally saved the half-screen snapped rect
            # as normalGeometry, replace it with a useful default normal size.
            looks_like_bad_saved = False
            if area is not None:
                looks_like_bad_saved = (abs(candidate.height() - area.height()) <= 24 and candidate.width() <= max(geom.width() + 80, int(area.width() * 0.62)))
            if candidate.width() < min_w or candidate.height() < min_h or looks_like_bad_saved:
                w = max(min_w, min(1280, int((area.width() if area else max(1280, geom.width())) * 0.68)))
                h = max(min_h, min(820, int((area.height() if area else max(820, geom.height())) * 0.72)))
                x = geom.x() + max(24, (geom.width() - w) // 2)
                y = geom.y() + 28
                return QRect(x, y, w, h)
            return QRect(candidate)
        except Exception:
            return QRect(candidate)

    def _coalesced_normal_geometry(self, key: str, candidate: QRect) -> QRect:
        """Keep intentional normal size stable across Windows maximize/snap restore.

        On frameless Windows, the native restore/drag loop may report the QML
        window a few pixels smaller than the remembered normal size because the
        non-client frame and DWM shadow are being collapsed.  If we save that
        tiny delta every time, each maximize -> drag-restore cycle looks like
        the window shrinks by one ring.  Preserve the previous width/height for
        small deltas, but keep the new x/y so normal dragging still records the
        final position.  Real user resizes are larger and still overwrite size.
        """
        key = str(key)
        previous = self._normal_geometries.get(key)
        if previous is None:
            return QRect(candidate)
        try:
            dw = abs(int(candidate.width()) - int(previous.width()))
            dh = abs(int(candidate.height()) - int(previous.height()))
            if dw <= 32 and dh <= 32:
                return QRect(int(candidate.x()), int(candidate.y()), int(previous.width()), int(previous.height()))
        except Exception:
            pass
        return QRect(candidate)

    def _geometry_matches(self, geom: QRect, target: QRect | None, tolerance: int = 3) -> bool:
        if target is None:
            return False
        try:
            return (abs(int(geom.x()) - int(target.x())) <= tolerance
                    and abs(int(geom.y()) - int(target.y())) <= tolerance
                    and abs(int(geom.width()) - int(target.width())) <= tolerance
                    and abs(int(geom.height()) - int(target.height())) <= tolerance)
        except Exception:
            return False

    def _raise_window(self, win: QWindow) -> None:
        for name in ("raise_", "raise"):
            try:
                fn = getattr(win, name, None)
                if callable(fn):
                    fn()
                    break
            except Exception:
                pass
        try:
            win.requestActivate()
        except Exception:
            pass

    def _key(self, win: QWindow) -> str:
        return str(win.property("windowKey") or win.objectName() or "window")

    def _is_maximized_or_fullscreen(self, win: QWindow) -> bool:
        return self._visibility_name(win) in {"maximized", "fullscreen"}

    def _visibility_name(self, win: QWindow) -> str:
        try:
            v = win.visibility()
        except Exception:
            return "normal"
        if sys.platform == "win32" and self._is_valid_window(win):
            try:
                if ctypes.windll.user32.IsZoomed(wintypes.HWND(int(win.winId()))):
                    return "maximized"
            except Exception:
                pass
        if v == QWindow.Visibility.Maximized:
            return "maximized"
        if v == QWindow.Visibility.FullScreen:
            return "fullscreen"
        if v == QWindow.Visibility.Minimized:
            return "minimized"
        s = str(v).lower()
        if "maximized" in s:
            return "maximized"
        if "fullscreen" in s or "full_screen" in s:
            return "fullscreen"
        if "minimized" in s:
            return "minimized"
        return "normal"

    def _send_windows_maximize_command(self, win: QWindow, restore: bool) -> bool:
        if not self._is_valid_window(win):
            return False
        try:
            hwnd = wintypes.HWND(int(win.winId()))
            if not hwnd:
                return False
            ctypes.windll.user32.SendMessageW(hwnd, WM_SYSCOMMAND, SC_RESTORE if restore else SC_MAXIMIZE, 0)
            return True
        except Exception:
            return False

    def _load_normal_geometry(self, key: str, win: QWindow) -> QRect:
        saved = self._settings.value_py(f"windows/{key}/normalGeometry", None)
        if isinstance(saved, dict):
            try:
                return QRect(int(saved["x"]), int(saved["y"]), int(saved["w"]), int(saved["h"]))
            except Exception:
                pass
        return QRect(win.x(), win.y(), max(900, win.width()), max(560, win.height()))

    def _is_valid_window(self, win: QWindow) -> bool:
        try:
            return win is not None and shiboken6.isValid(win)
        except Exception:
            return False

    def _safe_window_call(self, win: QWindow, method_name: str) -> None:
        if not self._is_valid_window(win):
            return
        try:
            method = getattr(win, method_name, None)
            if callable(method):
                method()
        except Exception:
            pass

    def _safe_set_geometry(self, win: QWindow, geom: QRect) -> None:
        if not self._is_valid_window(win):
            return
        try:
            win.setGeometry(geom)
        except Exception:
            pass

    def _minimum_size(self, win: QWindow) -> tuple[int, int]:
        min_w = 320
        min_h = 240
        for attr in ("minimumWidth", "minimumHeight"):
            try:
                value = getattr(win, attr)
                if callable(value):
                    value = value()
                if attr == "minimumWidth":
                    min_w = max(min_w, int(value))
                else:
                    min_h = max(min_h, int(value))
            except Exception:
                pass
        return min_w, min_h

    def _edge_value(self, edge) -> int:
        try:
            return int(edge.value)
        except Exception:
            try:
                return int(edge)
            except Exception:
                return 0

    def _apply_native_frame(self, win: QWindow) -> None:
        if not self._is_valid_window(win) or sys.platform != "win32":
            return
        try:
            hwnd = int(win.winId())
        except Exception:
            return
        if not hwnd:
            return
        self._hwnd_to_window[hwnd] = win
        try:
            self._enable_windows_shadow_style(hwnd)
            dwmapi = ctypes.windll.dwmapi
            hwnd_p = wintypes.HWND(hwnd)

            policy = ctypes.c_int(2)  # DWMNCRP_ENABLED
            try:
                dwmapi.DwmSetWindowAttribute(hwnd_p, 2, ctypes.byref(policy), ctypes.sizeof(policy))
            except Exception:
                pass

            class MARGINS(ctypes.Structure):
                _fields_ = [
                    ("cxLeftWidth", ctypes.c_int),
                    ("cxRightWidth", ctypes.c_int),
                    ("cyTopHeight", ctypes.c_int),
                    ("cyBottomHeight", ctypes.c_int),
                ]

            maximized = self._is_maximized_or_fullscreen(win)
            snapped = False
            try:
                snapped = str(self._settings.value_py(f"windows/{self._key(win)}/visibility", "")).startswith("snapped-") or self._looks_like_snapped_window(win, self._key(win))
            except Exception:
                snapped = False
            # A 1px DWM frame restores the native Windows shadow while the
            # custom QML chrome keeps ownership of the visible title bar.
            # Maximized/fullscreen/snapped windows keep zero margins to avoid
            # an inner shadow or a bright native resize line on the screen edge.
            margins = MARGINS(0, 0, 0, 0) if (maximized or snapped) else MARGINS(1, 1, 1, 1)
            try:
                dwmapi.DwmExtendFrameIntoClientArea(hwnd_p, ctypes.byref(margins))
            except Exception:
                pass

            try:
                corner_pref = ctypes.c_int(1 if maximized else 2)  # default rounded unless maximized
                dwmapi.DwmSetWindowAttribute(hwnd_p, 33, ctypes.byref(corner_pref), ctypes.sizeof(corner_pref))
            except Exception:
                pass

            try:
                border_none = ctypes.c_uint(0xFFFFFFFE)
                dwmapi.DwmSetWindowAttribute(hwnd_p, 34, ctypes.byref(border_none), ctypes.sizeof(border_none))
            except Exception:
                pass
        except Exception:
            return

    def _enable_windows_shadow_style(self, hwnd: int) -> None:
        try:
            user32 = ctypes.windll.user32
            GWL_STYLE = -16
            WS_THICKFRAME = 0x00040000
            WS_CAPTION = 0x00C00000
            WS_SYSMENU = 0x00080000
            WS_MINIMIZEBOX = 0x00020000
            WS_MAXIMIZEBOX = 0x00010000
            SWP_NOMOVE = 0x0002
            SWP_NOSIZE = 0x0001
            SWP_NOZORDER = 0x0004
            SWP_NOACTIVATE = 0x0010
            SWP_FRAMECHANGED = 0x0020
            if ctypes.sizeof(ctypes.c_void_p) == 8:
                get_long = user32.GetWindowLongPtrW
                set_long = user32.SetWindowLongPtrW
                get_long.restype = ctypes.c_longlong
                set_long.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_longlong]
            else:
                get_long = user32.GetWindowLongW
                set_long = user32.SetWindowLongW
                get_long.restype = ctypes.c_long
                set_long.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_long]
            hwnd_p = wintypes.HWND(hwnd)
            style = int(get_long(hwnd_p, GWL_STYLE))
            new_style = style | WS_THICKFRAME | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
            if new_style != style:
                set_long(hwnd_p, GWL_STYLE, new_style)
                user32.SetWindowPos(hwnd_p, None, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)
        except Exception:
            pass
