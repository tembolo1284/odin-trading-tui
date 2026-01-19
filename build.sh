#!/bin/bash

# Build the Odin matching engine client

set -e

cd "$(dirname "$0")"

echo "Building odin-trading-tui..."

mkdir -p bin

# Debug build
odin build src -out:bin/test_client -debug

echo "Build complete: bin/test_client"
echo ""
echo "Usage: ./bin/test_client"
echo ""
echo "Make sure your C matching engine is running on localhost:1234"
