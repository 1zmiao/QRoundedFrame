from __future__ import annotations

import os
import platform
import sys
import ctypes
from dataclasses import dataclass

from app.windows_compat import is_windows_11_or_newer


TRUE_VALUES = {"1", "true", "yes", "on"}
FALSE_VALUES = {"0", "false", "no", "off"}

# Linux custom chrome is intentionally opt-in per tested window manager/session.
# Add only environments that passed the full window behavior checklist.
LINUX_CUSTOM_CHROME_WM_ALLOWLIST: set[str] = {
    "gnome",  # GNOME on Xorg / Mutter verified for the Linux CSD shadow path.
    "cinnamon",  # Cinnamon on X11 / Muffin verified for the Linux CSD shadow path.
    "mate",  # MATE on X11 / Marco verified for the Linux CSD shadow path.
    "xfce",  # XFCE on X11 / Xfwm4 verified for the Linux CSD shadow path.
    "kde",  # KDE Plasma on X11 verified for the Linux CSD shadow path.
    "plasma",  # KDE Plasma session token used by some distributions.
}


@dataclass(frozen=True)
class WindowAppearancePolicy:
    platform: str
    session_type: str
    desktop: str
    wm_name: str
    custom_chrome: bool
    custom_shadow: bool
    external_shadow_supported: bool
    native_shell_preferred: bool
    shadow_policy: str
    corner_policy: str
    reason: str


def _env_text(name: str) -> str:
    return os.environ.get(name, "").strip()


def _env_bool(name: str) -> bool | None:
    value = _env_text(name).lower()
    if value in TRUE_VALUES:
        return True
    if value in FALSE_VALUES:
        return False
    return None


def _env_tokens(name: str) -> set[str]:
    raw = _env_text(name).lower()
    if not raw:
        return set()
    for sep in (";", ",", "|"):
        raw = raw.replace(sep, " ")
    return {part.strip() for part in raw.split() if part.strip()}


def _text_matches_any(text: str, tokens: set[str]) -> bool:
    if not text or not tokens:
        return False
    normalized = text.lower()
    return any(token and token in normalized for token in tokens)


def _linux_session_type() -> str:
    session = _env_text("XDG_SESSION_TYPE").lower()
    if session:
        return session
    if _env_text("WAYLAND_DISPLAY"):
        return "wayland"
    if _env_text("DISPLAY"):
        return "x11"
    return ""


def _linux_desktop() -> str:
    values = [
        _env_text("XDG_CURRENT_DESKTOP"),
        _env_text("XDG_SESSION_DESKTOP"),
        _env_text("DESKTOP_SESSION"),
    ]
    return ";".join(v for v in values if v).lower()


def _linux_wm_name() -> str:
    values = [
        _env_text("FRAMELESS_LINUX_WM"),
        _env_text("WINDOW_MANAGER"),
        _env_text("XDG_CURRENT_DESKTOP"),
    ]
    return ";".join(v for v in values if v).lower()


def _windows_display_fallback_needed(is_win11_or_newer: bool) -> bool:
    override = _env_bool("FRAMELESS_ASSUME_SYSTEM_CORNERS")
    if override is not None:
        return not override
    treat_vm_as_fallback = _env_bool("FRAMELESS_WINDOWS_VM_CUSTOM_CHROME") is True
    if sys.platform != "win32":
        return False
    try:
        class DISPLAY_DEVICEW(ctypes.Structure):
            _fields_ = [
                ("cb", ctypes.c_ulong),
                ("DeviceName", ctypes.c_wchar * 32),
                ("DeviceString", ctypes.c_wchar * 128),
                ("StateFlags", ctypes.c_ulong),
                ("DeviceID", ctypes.c_wchar * 128),
                ("DeviceKey", ctypes.c_wchar * 128),
            ]

        user32 = ctypes.windll.user32
        texts: list[str] = []
        index = 0
        while index < 16:
            device = DISPLAY_DEVICEW()
            device.cb = ctypes.sizeof(DISPLAY_DEVICEW)
            if not user32.EnumDisplayDevicesW(None, index, ctypes.byref(device), 0):
                break
            texts.extend([device.DeviceName, device.DeviceString, device.DeviceID])
            index += 1
        joined = " ".join(t for t in texts if t).lower()
        hard_fallback_markers = (
            "microsoft basic display",
            "microsoft remote display",
            "remote display",
            "virtual display",
        )
        vm_markers = (
            "vmware",
            "virtualbox",
            "hyper-v",
            "parallels",
            "virtio",
            "qxl",
        )
        if any(marker in joined for marker in hard_fallback_markers):
            return True
        if not is_win11_or_newer:
            return any(marker in joined for marker in vm_markers)
        return treat_vm_as_fallback and any(marker in joined for marker in vm_markers)
    except Exception:
        return False


def _linux_system_corners_trusted(desktop: str, wm_name: str) -> bool:
    override = _env_bool("FRAMELESS_ASSUME_SYSTEM_CORNERS")
    if override is not None:
        return override

    allowlist = set(LINUX_CUSTOM_CHROME_WM_ALLOWLIST)
    allowlist.update(_env_tokens("FRAMELESS_LINUX_CUSTOM_CHROME_WM"))
    if _text_matches_any(f"{desktop};{wm_name}", allowlist):
        return False

    # Linux window managers/compositors vary too much to infer by name. Keep
    # the default conservative: use system chrome unless a tested WM is in the
    # allowlist or the user explicitly forces custom chrome.
    return True


def _linux_gnome_headerbar_candidate(session: str, desktop: str, wm_name: str) -> bool:
    override = _env_bool("FRAMELESS_GNOME_HEADERBAR")
    if override is not None:
        return override
    if session != "x11":
        return False
    text = f"{desktop};{wm_name}"
    return _text_matches_any(text, {"gnome"})


def current_window_policy() -> WindowAppearancePolicy:
    force_native = _env_bool("FRAMELESS_ENABLE_NATIVE_WINDOW") is True
    force_legacy = _env_bool("FRAMELESS_FORCE_LEGACY_WINDOW") is True
    force_custom = _env_bool("FRAMELESS_FORCE_CUSTOM_CHROME") is True
    force_system = _env_bool("FRAMELESS_FORCE_SYSTEM_CHROME") is True

    if sys.platform == "win32":
        is_win11 = is_windows_11_or_newer()
        display_fallback = _windows_display_fallback_needed(is_win11)
        custom_chrome = force_custom or ((not is_win11 or display_fallback) and not force_system)
        if force_system:
            custom_chrome = False
        custom_shadow = custom_chrome
        native_shell = False if force_legacy else True
        reason = "Windows 11+ system chrome trusted"
        if force_system:
            reason = "System chrome forced by environment"
        elif display_fallback:
            reason = "Windows display fallback custom chrome"
        elif custom_chrome:
            reason = "Windows fallback custom chrome"
        return WindowAppearancePolicy(
            platform="windows",
            session_type="",
            desktop="windows",
            wm_name=f"windows-build-{platform.version()}",
            custom_chrome=custom_chrome,
            custom_shadow=custom_shadow,
            external_shadow_supported=custom_shadow,
            native_shell_preferred=native_shell,
            shadow_policy="custom-external" if custom_shadow else "system",
            corner_policy="rounded" if custom_chrome else "auto",
            reason=reason,
        )

    if sys.platform.startswith("linux"):
        session = _linux_session_type()
        desktop = _linux_desktop()
        wm_name = _linux_wm_name()
        trusted = _linux_system_corners_trusted(desktop, wm_name)
        gnome_headerbar = _linux_gnome_headerbar_candidate(session, desktop, wm_name)
        custom_chrome = force_custom or (not trusted and not force_system)
        if force_system:
            custom_chrome = False
        native_shell = False if force_legacy else (force_native or custom_chrome or (gnome_headerbar and not force_system))
        headerbar_shadow = gnome_headerbar and native_shell and not force_system and session != "wayland"
        external_shadow = (custom_chrome or headerbar_shadow) and session != "wayland"
        custom_shadow = custom_chrome or headerbar_shadow
        reason = "Linux system chrome conservative fallback"
        if force_custom:
            reason = "Linux custom chrome forced by environment"
        elif force_system:
            reason = "Linux system chrome forced by environment"
        elif custom_chrome:
            reason = "Linux custom chrome selected by tested WM allowlist"
        elif gnome_headerbar and native_shell:
            reason = "Linux GNOME headerbar system-behavior test"
        return WindowAppearancePolicy(
            platform="linux",
            session_type=session,
            desktop=desktop,
            wm_name=wm_name,
            custom_chrome=custom_chrome,
            custom_shadow=custom_shadow,
            external_shadow_supported=external_shadow,
            native_shell_preferred=native_shell,
            shadow_policy="custom-external" if external_shadow else ("none" if custom_chrome else "system"),
            corner_policy="rounded" if (custom_chrome or (gnome_headerbar and native_shell)) else "auto",
            reason=reason,
        )

    custom_chrome = force_custom and not force_system
    native_shell = False if force_legacy else (force_native or custom_chrome)
    return WindowAppearancePolicy(
        platform=sys.platform,
        session_type="",
        desktop="",
        wm_name="",
        custom_chrome=custom_chrome,
        custom_shadow=custom_chrome,
        external_shadow_supported=False,
        native_shell_preferred=native_shell,
        shadow_policy="none" if custom_chrome else "system",
        corner_policy="rounded" if custom_chrome else "auto",
        reason="Unsupported platform fallback",
    )


def use_custom_window_chrome() -> bool:
    return current_window_policy().custom_chrome


def use_custom_window_shadow() -> bool:
    return current_window_policy().custom_shadow


def external_shadow_supported() -> bool:
    return current_window_policy().external_shadow_supported


def native_window_shell_preferred() -> bool:
    return current_window_policy().native_shell_preferred
