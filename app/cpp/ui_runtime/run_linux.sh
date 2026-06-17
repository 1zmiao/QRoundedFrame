#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXE="$ROOT/build/cpp_ui/linux/bin/QRoundedFrame"

if [[ ! -x "$EXE" ]]; then
  bash "$ROOT/app/cpp/ui_runtime/build_linux.sh"
fi

export QROUNDEDFRAME_ROOT="${QROUNDEDFRAME_ROOT:-$ROOT}"
exec "$EXE" "$@"
