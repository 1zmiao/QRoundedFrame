from __future__ import annotations

import sys

from app.cpp_ui_launcher import launch_cpp_ui


def main(argv: list[str] | None = None) -> int:
    return int(launch_cpp_ui(list(sys.argv[1:] if argv is None else argv)) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
