#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/app/cpp/ui_runtime"
BUILD="$ROOT/build/cpp_ui/linux"

find_qt_cmake_prefix() {
  local prefix="$1"
  local config

  for config in \
    "$prefix/lib/cmake/Qt6/Qt6Config.cmake" \
    "$prefix/cmake/Qt6/Qt6Config.cmake" \
    "$prefix"/lib/*/cmake/Qt6/Qt6Config.cmake; do
    if [[ -f "$config" ]]; then
      dirname "$(dirname "$config")"
      return 0
    fi
  done

  return 1
}

QT_PREFIX=""
QT_CMAKE_PREFIX=""

if [[ -n "${FRAMELESS_QT_PREFIX:-}" ]]; then
  QT_PREFIX="$FRAMELESS_QT_PREFIX"
  QT_CMAKE_PREFIX="$(find_qt_cmake_prefix "$QT_PREFIX" || true)"
else
  QT_CANDIDATES=()
  if command -v qmake6 >/dev/null 2>&1; then
    QT_CANDIDATES+=("$(qmake6 -query QT_INSTALL_PREFIX)")
  fi
  if command -v qtpaths6 >/dev/null 2>&1; then
    QT_CANDIDATES+=("$(qtpaths6 --qt-query QT_INSTALL_PREFIX)")
  fi
  QT_CANDIDATES+=("/usr")

  for candidate in "${QT_CANDIDATES[@]}"; do
    [[ -n "$candidate" ]] || continue
    if QT_CMAKE_PREFIX="$(find_qt_cmake_prefix "$candidate")"; then
      QT_PREFIX="$candidate"
      break
    fi
  done
fi

if [[ -z "$QT_CMAKE_PREFIX" ]]; then
  echo "Qt 6 CMake package not found under: $QT_PREFIX" >&2
  echo "Set FRAMELESS_QT_PREFIX=/path/to/Qt/6.x/gcc_64 or install Qt 6 development packages." >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake not found. Install cmake first." >&2
  exit 1
fi

if command -v ninja >/dev/null 2>&1; then
  GENERATOR=(-G Ninja)
  BUILD_EXTRA=(-DCMAKE_MAKE_PROGRAM="$(command -v ninja)")
else
  GENERATOR=(-G "Unix Makefiles")
  BUILD_EXTRA=()
fi

echo "Using Qt prefix: $QT_PREFIX"
echo "Using Qt CMake prefix: $QT_CMAKE_PREFIX"

cmake -S "$SRC" -B "$BUILD" "${GENERATOR[@]}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$QT_CMAKE_PREFIX" \
  "${BUILD_EXTRA[@]}"
cmake --build "$BUILD" --config Release

echo "Built: $BUILD/bin/QRoundedFrame"
