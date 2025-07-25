#!/usr/bin/env python3
import subprocess
import time
import sys

# Start the debugger
proc = subprocess.Popen(['.build/debug/outbox-debug'], 
                       stdin=subprocess.PIPE, 
                       stdout=subprocess.PIPE, 
                       stderr=subprocess.STDOUT,
                       text=True)

# Give it time to initialize
time.sleep(3)

# Send exit command
proc.stdin.write('exit\n')
proc.stdin.flush()

# Wait a bit more
time.sleep(1)

# Terminate if still running
proc.terminate()

# Get output
output, _ = proc.communicate()

# Filter and print relevant lines
for line in output.split('\n'):
    # Remove ANSI escape codes
    import re
    clean_line = re.sub(r'\x1b\[[0-9;]*m', '', line)
    clean_line = re.sub(r'\x1b\[[0-9;]*H', '', clean_line)
    clean_line = re.sub(r'\x1b\[.*?h', '', clean_line)
    clean_line = re.sub(r'\x1b\[.*?l', '', clean_line)
    
    # Print lines with debug info
    if any(emoji in clean_line for emoji in ['🚀', '📝', '🔄', '🔌', '✅', '❌', '➡️', '📊', '⚠️']):
        print(clean_line.strip())