from __future__ import annotations

import sys
from pathlib import Path

try:
    from PySide6.QtQml import QJSValue
except Exception:  # pragma: no cover
    QJSValue = None


def to_python(value):
    if QJSValue is not None and isinstance(value, QJSValue):
        return value.toVariant()
    return value


def app_root() -> Path:
    """Return the application root directory.

    In source mode this is the project directory. In frozen mode this is the
    directory containing the executable, so user_data stays next to the app.
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[2]


def app_data_dir() -> Path:
    """Local data directory used by this template.

    The user requested demo configuration files to be generated under the
    software root instead of the OS AppConfigLocation/C: drive path.
    """
    path = app_root() / "user_data"
    path.mkdir(parents=True, exist_ok=True)
    return path
