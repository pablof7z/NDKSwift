#!/bin/bash
# Test script for OutboxDebugger REPL mode

echo "Testing OutboxDebugger REPL mode..."
echo ""
echo "This script will:"
echo "1. Build the OutboxDebugger"
echo "2. Run it in REPL mode"
echo ""

# Build the tool
echo "Building OutboxDebugger..."
cd "$(dirname "$0")"
swift build --product outbox-debug

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo ""
echo "Starting REPL mode..."
echo "Try commands like:"
echo "  track npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
echo "  outbox npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
echo "  req npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
echo "  quit"
echo ""

# Run in REPL mode
.build/debug/outbox-debug repl