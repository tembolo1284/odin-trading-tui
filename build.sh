#!/usr/bin/env bash

set -e

PROJECT_NAME="test_client"
SRC_DIR="src"
BIN_DIR="bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${CYAN}==>${NC} $1"; }
print_success() { echo -e "${GREEN}==>${NC} $1"; }
print_error() { echo -e "${RED}==>${NC} $1"; }

cmd_build() {
    mkdir -p "$BIN_DIR"
    print_status "Building $PROJECT_NAME..."
    
    local flags="-debug"
    if [[ "$1" == "release" ]]; then
        flags="-o:speed -disable-assert -no-bounds-check"
    fi
    
    echo -e "${CYAN}==>${NC} odin build $SRC_DIR -out:$BIN_DIR/$PROJECT_NAME $flags"
    odin build "$SRC_DIR" \
        -out:"$BIN_DIR/$PROJECT_NAME" \
        $flags \
        -strict-style \
        -vet-style \
        -show-timings \
        -warnings-as-errors
    
    print_success "Build complete: $BIN_DIR/$PROJECT_NAME"
}

cmd_run() {
    if [[ ! -f "$BIN_DIR/$PROJECT_NAME" ]]; then
        cmd_build
    fi
    print_status "Running: $BIN_DIR/$PROJECT_NAME $*"
    "$BIN_DIR/$PROJECT_NAME" "$@"
}

cmd_clean() {
    print_status "Cleaning..."
    rm -rf "$BIN_DIR"
    print_success "Cleaned"
}

cmd_scenario() {
    local scenario="$1"
    local host="${2:-127.0.0.1}"
    local port="${3:-1234}"
    
    if [[ -z "$scenario" ]]; then
        print_error "Usage: ./build.sh scenario <num> [host] [port]"
        echo ""
        echo "Scenarios:"
        echo "  1   Simple orders (no match) + Flush"
        echo "  2   Matching orders"
        echo "  3   Order + Cancel"
        echo "  20  Stress: 2k orders / 1k trades"
        echo "  21  Stress: 20k orders / 10k trades"
        echo "  22  Stress: 200k orders / 100k trades"
        echo "  30  Dual symbol: 2k orders"
        echo "  31  Dual symbol: 20k orders"
        return 1
    fi
    
    if [[ ! -f "$BIN_DIR/$PROJECT_NAME" ]]; then
        cmd_build
    fi
    
    print_status "Running scenario $scenario against $host:$port"
    "$BIN_DIR/$PROJECT_NAME" "$scenario" "$host" "$port"
}

cmd_help() {
    cat << EOF
Usage: ./build.sh <command> [args]

Commands:
    build [release]           Build the client (debug by default)
    run [args]                Build and run with arguments
    clean                     Remove build artifacts
    scenario <n> [host] [port]  Run scenario N against server
    help                      Show this message

Scenario shortcuts:
    ./build.sh scenario 1                 # Basic no-match test
    ./build.sh scenario 2                 # Matching orders
    ./build.sh scenario 20                # 2k order stress test
    ./build.sh scenario 30                # Dual-symbol test
    ./build.sh scenario 21 192.168.1.5    # Remote server

Examples:
    ./build.sh build
    ./build.sh build release
    ./build.sh scenario 1
    ./build.sh scenario 20 localhost 1234
EOF
}

# ============================================================================
# Main
# ============================================================================

cd "$(dirname "$0")"

case "${1:---help}" in
    build|--build)
        cmd_build "$2"
        ;;
    run|--run)
        shift
        cmd_run "$@"
        ;;
    clean|--clean)
        cmd_clean
        ;;
    scenario|--scenario)
        shift
        cmd_scenario "$@"
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        # If first arg is a number, assume it's a scenario
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            cmd_scenario "$@"
        else
            print_error "Unknown command: $1"
            cmd_help
            exit 1
        fi
        ;;
esac
