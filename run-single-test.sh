#!/bin/bash

TEST=$1
echo -n "Testing $TEST... "

# Run test in background
swift test --filter "Bech32Tests/$TEST" > /tmp/test-output.txt 2>&1 &
PID=$!

# Wait up to 5 seconds
SECONDS=0
while [ $SECONDS -lt 5 ] && kill -0 $PID 2>/dev/null; do
  sleep 0.1
done

if kill -0 $PID 2>/dev/null; then
  # Still running, kill it
  kill -9 $PID 2>/dev/null
  echo "TIMEOUT"
else
  # Check if it passed
  if grep -q "passed" /tmp/test-output.txt; then
    echo "PASSED"
  else
    echo "FAILED"
    tail -10 /tmp/test-output.txt
  fi
fi