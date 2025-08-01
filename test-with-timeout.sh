#!/bin/bash

# Simple timeout script for testing
# Usage: ./test-with-timeout.sh <timeout_seconds> <test_filter>

TIMEOUT="${1:-30}"
FILTER="${2:-}"

if [ -z "$FILTER" ]; then
    echo "Usage: $0 <timeout_seconds> <test_filter>"
    echo "Example: $0 30 Bech32Tests"
    exit 1
fi

echo "Running tests matching '$FILTER' with ${TIMEOUT}s timeout..."

# Run the test in background
swift test --filter "$FILTER" 2>&1 &
PID=$!

# Wait for timeout
sleep "$TIMEOUT" &
SLEEP_PID=$!

# Wait for either test to complete or timeout
wait -n $PID $SLEEP_PID 2>/dev/null
RESULT=$?

# Check which process finished
if kill -0 $PID 2>/dev/null; then
    # Test is still running, kill it
    echo ""
    echo "⏱️  TIMEOUT: Test exceeded ${TIMEOUT}s limit"
    kill -TERM $PID 2>/dev/null
    sleep 1
    kill -KILL $PID 2>/dev/null
    exit 1
else
    # Test completed, kill the sleep
    kill $SLEEP_PID 2>/dev/null
    exit $RESULT
fi