# build.sh
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"
OUT_BIN="$BIN_DIR/test_client"

MODE="debug"          # debug | release
DO_CLEAN=0
DO_BUILD=0
DO_RUN=0
DO_TEST=0

DO_STRICT_STYLE=1
DO_VET_STYLE=1

EXTRA_FLAGS=()

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--clean] [--build] [--run] [--test] [--debug|--release]
             [--no-strict-style] [--no-vet-style] [-- <extra odin flags...>]

Note:
  This script builds from ./src, so imports inside src should look like:
    import "client/protocol_binary"
EOF
}

die() { echo "error: $*" >&2; exit 1; }

if [[ $# -eq 0 ]]; then
  DO_BUILD=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --clean) DO_CLEAN=1; shift ;;
    --build) DO_BUILD=1; shift ;;
    --run) DO_RUN=1; DO_BUILD=1; shift ;;
    --test) DO_TEST=1; shift ;;
    --debug) MODE="debug"; shift ;;
    --release) MODE="release"; shift ;;
    --no-strict-style) DO_STRICT_STYLE=0; shift ;;
    --no-vet-style) DO_VET_STYLE=0; shift ;;
    --) shift; EXTRA_FLAGS+=("$@"); break ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

cd "$ROOT_DIR"
mkdir -p "$BIN_DIR"

if [[ $DO_CLEAN -eq 1 ]]; then
  echo "==> Cleaning: $BIN_DIR"
  rm -rf "$BIN_DIR"
  mkdir -p "$BIN_DIR"
fi

odin_flags=()
if [[ "$MODE" == "debug" ]]; then
  odin_flags+=("-debug")
else
  odin_flags+=("-o:speed")
fi

if [[ $DO_STRICT_STYLE -eq 1 ]]; then
  odin_flags+=("-strict-style")
fi
if [[ $DO_VET_STYLE -eq 1 ]]; then
  odin_flags+=("-vet-style")
fi

odin_flags+=("-show-timings")
odin_flags+=("-warnings-as-errors")
odin_flags+=("${EXTRA_FLAGS[@]}")

if [[ $DO_BUILD -eq 1 ]]; then
  echo "==> Building odin-trading-tui..."
  echo "==> odin build src -out:$OUT_BIN ${odin_flags[*]}"
  odin build src -out:"$OUT_BIN" "${odin_flags[@]}"
  echo "==> Build complete: $OUT_BIN"
fi

if [[ $DO_TEST -eq 1 ]]; then
  echo "==> Testing odin-trading-tui..."
  echo "==> odin test src ${odin_flags[*]}"
  odin test src "${odin_flags[@]}"
fi

if [[ $DO_RUN -eq 1 ]]; then
  echo "==> Running: $OUT_BIN"
  exec "$OUT_BIN"
fi

