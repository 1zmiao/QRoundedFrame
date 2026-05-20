from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, Property, Signal, Slot

from .util import app_data_dir, to_python


class SettingsStore(QObject):
    changed = Signal(str, object)
    revisionChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._base = app_data_dir() / "config"
        self._base.mkdir(parents=True, exist_ok=True)
        self._file = self._base / "settings.json"
        self._data = self._load()
        self._revision = 0


    @Property(int, notify=revisionChanged)
    def revision(self) -> int:
        return self._revision

    @Property(str, constant=True)
    def configDir(self) -> str:
        return str(self._base)

    @Slot(str, result="QVariant")
    def value(self, key: str):
        return self.value_py(key, None)

    @Slot(str, "QVariant", result="QVariant")
    def valueOr(self, key: str, default):
        return self.value_py(key, to_python(default))

    @Slot(str, "QVariant")
    def setValue(self, key: str, value) -> None:
        self.set_value_py(key, to_python(value))

    @Slot(str)
    def remove(self, key: str) -> None:
        self.remove_value_py(key)

    @Slot(result=str)
    def path(self) -> str:
        return str(self._file)

    def value_py(self, key: str, default: Any = None) -> Any:
        cur: Any = self._data
        for part in key.split("/"):
            if not isinstance(cur, dict) or part not in cur:
                return default
            cur = cur[part]
        return cur

    def set_value_py(self, key: str, value: Any) -> None:
        cur = self._data
        parts = [p for p in key.split("/") if p]
        for part in parts[:-1]:
            cur = cur.setdefault(part, {})
        if not parts:
            return
        cur[parts[-1]] = value
        self._save()
        self._revision += 1
        self.revisionChanged.emit()
        self.changed.emit(key, value)


    def remove_value_py(self, key: str) -> None:
        parts = [p for p in key.split("/") if p]
        if not parts:
            return
        cur = self._data
        for part in parts[:-1]:
            if not isinstance(cur, dict) or part not in cur:
                return
            cur = cur[part]
        if isinstance(cur, dict) and parts[-1] in cur:
            cur.pop(parts[-1], None)
            self._save()
            self._revision += 1
            self.revisionChanged.emit()
            self.changed.emit(key, None)

    def _load(self) -> dict:
        if not self._file.exists():
            return {}
        try:
            return json.loads(self._file.read_text(encoding="utf-8"))
        except Exception:
            backup = self._file.with_suffix(".broken.json")
            try:
                self._file.replace(backup)
            except Exception:
                pass
            return {}

    def _save(self) -> None:
        self._base.mkdir(parents=True, exist_ok=True)
        tmp = self._file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(self._file)
