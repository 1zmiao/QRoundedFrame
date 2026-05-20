from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from PySide6.QtCore import QObject, Property, Signal, Slot

from .util import app_data_dir, to_python


class SecretStore(QObject):
    unlockedChanged = Signal(bool)

    def __init__(self, password: str | None = None, parent=None):
        super().__init__(parent)
        self._base = app_data_dir() / "secure"
        self._base.mkdir(parents=True, exist_ok=True)
        self._meta_file = self._base / "vault.meta"
        self._vault_file = self._base / "secrets.bin"
        self._password_mode = password is not None
        self._fernet_key = self._load_or_create_key(password)
        self._fernet = Fernet(self._fernet_key)

    @Property(str, constant=True)
    def secureDir(self) -> str:
        return str(self._base)

    @Property(str, constant=True)
    def vaultFile(self) -> str:
        return str(self._vault_file)

    @Slot(str, "QVariant")
    def put(self, key: str, value) -> None:
        self.put_py(key, to_python(value))

    @Slot(str, result="QVariant")
    def get(self, key: str):
        return self.get_py(key)

    @Slot(str)
    def remove(self, key: str) -> None:
        data = self._read_vault()
        if key in data:
            data.pop(key, None)
            self._write_vault(data)

    @Slot(result=str)
    def path(self) -> str:
        return str(self._base)

    def put_py(self, key: str, value: Any) -> None:
        data = self._read_vault()
        data[str(key)] = value
        self._write_vault(data)

    def get_py(self, key: str):
        data = self._read_vault()
        return data.get(str(key))

    def _read_vault(self) -> dict[str, Any]:
        if not self._vault_file.exists() or self._vault_file.stat().st_size == 0:
            return {}
        try:
            payload = self._fernet.decrypt(self._vault_file.read_bytes())
            data = json.loads(payload.decode("utf-8"))
            return data if isinstance(data, dict) else {}
        except InvalidToken as exc:
            raise ValueError("Wrong password or damaged encrypted file") from exc
        except json.JSONDecodeError as exc:
            raise ValueError("Damaged encrypted JSON payload") from exc

    def _write_vault(self, data: dict[str, Any]) -> None:
        self._base.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        token = self._fernet.encrypt(payload)
        tmp = self._vault_file.with_suffix(".tmp")
        tmp.write_bytes(token)
        tmp.replace(self._vault_file)
        try:
            os.chmod(self._vault_file, 0o600)
        except OSError:
            pass

    def _load_or_create_key(self, password: str | None) -> bytes:
        if password:
            meta = self._load_or_create_meta()
            return self._derive_key_from_password(
                password=password,
                salt=base64.b64decode(meta["salt"]),
                iterations=int(meta["iterations"]),
            )

        key_file = self._base / "master.key"
        if key_file.exists():
            return key_file.read_bytes()

        key = Fernet.generate_key()
        key_file.write_bytes(key)
        try:
            os.chmod(key_file, 0o600)
        except OSError:
            pass
        return key

    def _load_or_create_meta(self) -> dict:
        if self._meta_file.exists():
            return json.loads(self._meta_file.read_text(encoding="utf-8"))

        meta = {
            "version": 1,
            "kdf": "PBKDF2-HMAC-SHA256",
            "salt": base64.b64encode(os.urandom(16)).decode("ascii"),
            "iterations": 600000,
        }
        self._meta_file.write_text(json.dumps(meta, indent=2), encoding="utf-8")
        return meta

    def _derive_key_from_password(self, password: str, salt: bytes, iterations: int) -> bytes:
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=iterations,
        )
        raw = kdf.derive(password.encode("utf-8"))
        return base64.urlsafe_b64encode(raw)
