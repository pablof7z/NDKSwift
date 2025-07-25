#!/bin/bash
# Test initialization output
echo "exit" | timeout 5 .build/debug/outbox-debug 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "(🚀|📝|🔄|🔌|✅|❌|➡️|📊)" | head -20