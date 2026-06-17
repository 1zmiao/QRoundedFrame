from __future__ import annotations

import subprocess
import sys
import tempfile
import textwrap
import time
from pathlib import Path

from memory_child_probe import memory_sample


ROOT = Path(__file__).resolve().parents[1]


def run_case(label: str, code: str, delay: float = 2.0) -> dict[str, float]:
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as handle:
        handle.write(code)
        path = Path(handle.name)
    proc = subprocess.Popen([sys.executable, str(path)], cwd=ROOT)
    try:
        time.sleep(delay)
        sample = memory_sample(proc.pid)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        try:
            path.unlink(missing_ok=True)
        except Exception:
            pass
    print(f"{label}_mb={sample}", flush=True)
    return sample


def main() -> int:
    python_only = """
import time
time.sleep(20)
"""
    qgui_only = """
import sys, time
from PySide6.QtGui import QGuiApplication
from PySide6.QtCore import QTimer
app = QGuiApplication(sys.argv)
QTimer.singleShot(20000, app.quit)
app.exec()
"""
    quick_window = """
import sys
from PySide6.QtCore import QTimer, QUrl
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtGui import QGuiApplication
app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.loadData(b'import QtQuick\\nWindow { width: 936; height: 749; visible: true; color: "#f8f7fc" }', QUrl('inline.qml'))
QTimer.singleShot(20000, app.quit)
app.exec()
"""
    controls_window = """
import sys
from PySide6.QtCore import QTimer, QUrl
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuickControls2 import QQuickStyle
QQuickStyle.setStyle('Basic')
app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.loadData(b'import QtQuick\\nimport QtQuick.Controls\\nWindow { width: 936; height: 749; visible: true; Rectangle { anchors.fill: parent; color: "#f8f7fc"; Button { text: "Test"; anchors.centerIn: parent } } }', QUrl('inline.qml'))
QTimer.singleShot(20000, app.quit)
app.exec()
"""
    cases = [
        ("python_only", python_only),
        ("qgui_only", qgui_only),
        ("quick_window", quick_window),
        ("controls_window", controls_window),
    ]
    for label, code in cases:
        run_case(label, textwrap.dedent(code).strip() + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
