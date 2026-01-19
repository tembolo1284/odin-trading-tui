#!/usr/bin/env bash
#
# build.sh - Build / run helper for odin-trading-tui
#
# Usage:
#   ./build.sh --build
#   ./build.sh --run
#   ./build.sh --clean
#   ./build.sh --clean --build --run
#
# Options:
#   --release          Build in release mode (default: debug)
#   --out <name>       Output binary name (default: test_client)
#   --args "<args>"    Args passed to the program when using --run
#   --                 Everything after -- is passed to the program
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN_DIR="${SCRIPT_DIR}/bin"
OUT_NAME="test_client"
MODE="debug"

DO_CLEAN=0
DO_BUILD=0
DO_RUN=0

PROG_ARGS=()

usage() {
  cat <<'EOF'
build.sh - Build / run helper for odin-trading-tui

Usage:
  ./build.sh --build
  ./build.sh --run
  ./build.sh --clean
  ./build.sh --clean --build --run

Options:
  --release          Build in release mode (default: debug)
  --out <name>       Output binary name (default: test_client)
  --args "<args>"    Args passed to the program when using --run
  --                 Everything after -- is passed to the program

Examples:
  ./build.sh --build
  ./build.sh --clean --build
  ./build.sh --run
  ./build.sh --clean --build --run -- --host=localhost --port=1234
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

if ! command -v odin >/dev/null 2>&1; then
  die "odin not found in PATH"
fi

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)   DO_CLEAN=1; shift ;;
    --build)   DO_BUILD=1; shift ;;
    --run)     DO_RUN=1; shift ;;
    --release) MODE="release"; shift ;;
    --debug)   MODE="debug"; shift ;;
    --out)
      [[ $# -ge 2 ]] || die "--out requires a value"
      OUT_NAME="$2"
      shift 2
      ;;
    --args)
      [[ $# -ge 2 ]] || die "--args requires a value"
      # shellcheck disable=SC2206
      PROG_ARGS+=($2)
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        PROG_ARGS+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

# Default behavior: build if nothing selected
if [[ $DO_CLEAN -eq 0 && $DO_BUILD -eq 0 && $DO_RUN -eq 0 ]]; then
  DO_BUILD=1
fi

BIN_PATH="${BIN_DIR}/${OUT_NAME}"

clean() {
  echo "==> Cleaning..."
  rm -rf "$BIN_DIR"
  mkdir -p "$BIN_DIR"
}

build() {
  echo "==> Building (${MODE})..."
  mkdir -p "$BIN_DIR"

  ODIN_FLAGS=()
  if [[ "$MODE" == "debug" ]]; then
    ODIN_FLAGS+=("-debug")
  else
    ODIN_FLAGS+=("-o:speed")
  fi

  # Build the whole src package
  odin build src -out:"$BIN_PATH" "${ODIN_FLAGS[@]}"

  echo "==> Built: $BIN_PATH"
}

run() {
  [[ -x "$BIN_PATH" ]] || die "Binary not found or not executable: $BIN_PATH (run with --build first)"
  echo "==> Running: $BIN_PATH ${PROG_ARGS[*]:-}"
  "$BIN_PATH" "${PROG_ARGS[@]}"
}

if [[ $DO_CLEAN -eq 1 ]]; then clean; fi
if [[ $DO_BUILD -eq 1 ]]; then build; fi
if [[ $DO_RUN -eq 1 ]]; then run; fi

