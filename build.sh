#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  build         Build the client (release)"
    echo "  debug         Build with debug info"
    echo "  clean         Remove build artifacts"
    echo "  test          Run tests"
    echo "  run           Run the client"
    echo "  decoder       Build and run the decoder"
    echo "  help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 build"
    echo "  $0 run localhost 1234"
    echo "  $0 run localhost 1234 2 --tcp"
    echo "  $0 test"
}

cmd_build() {
    echo -e "${GREEN}Building client (release)...${NC}"
    mkdir -p "$BUILD_DIR"
    odin build "$PROJECT_DIR/src/client" \
        -out:"$BUILD_DIR/client" \
        -o:speed \
        -disable-assert
    echo -e "${GREEN}Built: $BUILD_DIR/client${NC}"
}

cmd_debug() {
    echo -e "${YELLOW}Building client (debug)...${NC}"
    mkdir -p "$BUILD_DIR"
    odin build "$PROJECT_DIR/src/client" \
        -out:"$BUILD_DIR/client" \
        -debug
    echo -e "${GREEN}Built: $BUILD_DIR/client${NC}"
}

cmd_clean() {
    echo -e "${YELLOW}Cleaning...${NC}"
    rm -rf "$BUILD_DIR"
    echo -e "${GREEN}Clean complete${NC}"
}

cmd_test() {
    echo -e "${GREEN}Running tests...${NC}"
    odin test "$PROJECT_DIR/tests" \
        -all-packages
    echo -e "${GREEN}Tests complete${NC}"
}

cmd_run() {
    if [ ! -f "$BUILD_DIR/client" ]; then
        cmd_build
    fi
    
    echo -e "${GREEN}Running client...${NC}"
    "$BUILD_DIR/client" "$@"
}

cmd_decoder() {
    echo -e "${GREEN}Building decoder...${NC}"
    mkdir -p "$BUILD_DIR"
    odin build "$PROJECT_DIR/src/decoder" \
        -out:"$BUILD_DIR/decoder" \
        -o:speed
    echo -e "${GREEN}Built: $BUILD_DIR/decoder${NC}"
    
    if [ $# -gt 0 ]; then
        "$BUILD_DIR/decoder" "$@"
    fi
}

case "${1:-help}" in
    build)
        cmd_build
        ;;
    debug)
        cmd_debug
        ;;
    clean)
        cmd_clean
        ;;
    test)
        cmd_test
        ;;
    run)
        shift
        cmd_run "$@"
        ;;
    decoder)
        shift
        cmd_decoder "$@"
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        print_usage
        exit 1
        ;;
esac
