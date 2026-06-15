from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TARGETS = ("app", "qml", "scripts", "README.md")
SKIP_PARTS = {
    ".codex_backups",
    ".git",
    "__pycache__",
    "app/prebuilt",
    "app/cpp/frameless_native/build-custom",
    "app/cpp/frameless_native/build-system",
    "third_party",
}
TEXT_SUFFIXES = {
    ".py",
    ".qml",
    ".js",
    ".json",
    ".md",
    ".txt",
    ".toml",
    ".ini",
    ".cmake",
    ".cpp",
    ".h",
    ".hpp",
}
MOJIBAKE_MARKERS = (
    "\u935a",
    "\u59dd",
    "\u9477",
    "\u7941",
    "\u7c8d",
    "\u5bf0",
    "\u93c5",
    "\u923b",
    "\u00c3",
    "\u00c2",
    "\u00e2",
    "\u00e5",
    "\u00e6",
    "\u00e7",
    "\u00e9",
    "\u00e8",
    "\u00e4",
    "\ufffd",
)


def should_skip(path: Path) -> bool:
    relative = path.relative_to(ROOT).as_posix()
    return any(relative == part or relative.startswith(part + "/") for part in SKIP_PARTS)


def iter_files(targets: list[str]):
    for target in targets:
        path = (ROOT / target).resolve()
        if not path.exists() or should_skip(path):
            continue
        if path.is_file():
            if path.suffix.lower() in TEXT_SUFFIXES:
                yield path
            continue
        for item in path.rglob("*"):
            if item.is_file() and item.suffix.lower() in TEXT_SUFFIXES and not should_skip(item):
                yield item


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass

    parser = argparse.ArgumentParser(description="Scan maintained source files for common mojibake markers.")
    parser.add_argument("targets", nargs="*", default=list(DEFAULT_TARGETS))
    args = parser.parse_args()

    hits: list[tuple[Path, int, str]] = []
    for path in iter_files(args.targets):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            hits.append((path, 0, f"UTF-8 decode failed: {exc}"))
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if any(marker in line for marker in MOJIBAKE_MARKERS):
                hits.append((path, lineno, line.strip()))

    for path, lineno, line in hits:
        relative = path.relative_to(ROOT)
        print(f"{relative}:{lineno}: {line}")
    return 1 if hits else 0


if __name__ == "__main__":
    raise SystemExit(main())
