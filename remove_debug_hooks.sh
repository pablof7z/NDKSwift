#!/bin/bash

# This script removes all OUTBOX_DEBUG_HOOK code from NDKSwift

echo "Removing debug hooks from NDKSwift..."

# Files to process
files=(
    "Sources/NDKSwift/Core/Utilities/NDKLogger.swift"
    "Sources/NDKSwift/DataSource/NDKDataRequirementManager.swift"
    "Sources/NDKSwift/Relay/NDKRelayConnection.swift"
    "Sources/NDKSwift/Outbox/NDKOutboxManager.swift"
    "Sources/NDKSwift/Core/NDK.swift"
    "Sources/NDKSwift/DataSource/InternalSubscription.swift"
    "Sources/NDKSwift/DataSource/NDKDataSource.swift"
    "Sources/NDKSwift/Models/NDKRelay.swift"
    "Sources/NDKSwift/Core/Managers/NDKPool.swift"
)

for file in "${files[@]}"; do
    echo "Processing $file..."
    
    # Create temp file
    temp_file=$(mktemp)
    
    # Process file
    awk '
    /\/\/ MARK: - OUTBOX_DEBUG_HOOK/ {
        in_debug_block = 1
        next
    }
    in_debug_block && /^[[:space:]]*$/ {
        # Empty line after debug block
        in_debug_block = 0
        next
    }
    in_debug_block && /await NDKDebugHooks\.emit/ {
        next
    }
    in_debug_block && /NDKDebugHooks\.setDebugHook/ {
        next
    }
    !in_debug_block {
        print
    }
    ' "$file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$file"
done

echo "Debug hooks removed!"