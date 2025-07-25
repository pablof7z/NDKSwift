#!/usr/bin/env python3
import subprocess
import time
import sys
import re

def clean_ansi(text):
    """Remove ANSI escape codes while preserving content"""
    # Remove cursor movement and control codes
    text = re.sub(r'\x1b\[\d+;\d+H', '', text)  # Cursor position
    text = re.sub(r'\x1b\[\d+[A-Z]', '', text)   # Cursor movement
    text = re.sub(r'\x1b\[[?]\d+[hl]', '', text) # Show/hide cursor
    text = re.sub(r'\x1b\[2J', '\n', text)       # Clear screen -> newline
    text = re.sub(r'\x1b\[\d+m', '', text)       # Color codes
    text = re.sub(r'\x1b\[[^m]*m', '', text)     # Other formatting
    return text

# Start the debugger
proc = subprocess.Popen(['.build/debug/outbox-debug'], 
                       stdin=subprocess.PIPE, 
                       stdout=subprocess.PIPE, 
                       stderr=subprocess.STDOUT,
                       text=True)

# Give it time to initialize
time.sleep(3)

# Send a req command
print("=== Sending: req npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft ===\n")
proc.stdin.write('req npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft\n')
proc.stdin.flush()

# Wait for processing
time.sleep(8)

# Send exit
proc.stdin.write('exit\n')
proc.stdin.flush()
time.sleep(1)

# Terminate
proc.terminate()

# Get output
output, _ = proc.communicate()

# Clean and process output
clean_output = clean_ansi(output)

# Extract the interesting parts after the req command
lines = clean_output.split('\n')
in_req_output = False
relevant_lines = []

for line in lines:
    if 'Processing: req' in line:
        in_req_output = True
        relevant_lines.append("🎯 " + line.strip())
    elif in_req_output and line.strip():
        # Skip UI border lines
        if not any(char in line for char in ['┌', '┐', '└', '┘', '│', '─']):
            relevant_lines.append(line.strip())

# Print the relevant output
print("\n".join(relevant_lines[:50]))  # Limit to first 50 lines