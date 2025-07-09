#!/bin/bash
# Run the NWC balance check with a timeout

echo "Starting NWC Balance Check..."
./.build/debug/NWCBalanceCheck &
PID=$!

# Wait for 15 seconds
sleep 15

# Check if process is still running
if ps -p $PID > /dev/null; then
    echo -e "\n⏱️ Process timed out after 15 seconds"
    kill $PID
else
    echo -e "\n✅ Process completed"
fi