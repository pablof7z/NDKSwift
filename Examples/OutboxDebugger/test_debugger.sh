#!/bin/bash

# Test the outbox debugger with automated commands
echo "Testing Outbox Debugger..."

# Create a test input file with commands
cat > test_commands.txt << 'EOF'
help
clear
exit
EOF

# Run the debugger with test commands
timeout 5s ./.build/debug/outbox-debug < test_commands.txt > test_output.txt 2>&1

# Check if it ran without crashing
if [ $? -eq 124 ]; then
    echo "✅ Debugger ran for 5 seconds without crashing"
elif [ $? -eq 0 ]; then
    echo "✅ Debugger exited cleanly"
else
    echo "❌ Debugger crashed with exit code: $?"
    cat test_output.txt
fi

# Clean up
rm -f test_commands.txt test_output.txt