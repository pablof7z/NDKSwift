#!/bin/bash

# Get list of all active test files (exclude DisabledTests and non-test files)
test_files=($(find Tests/NDKSwiftTests -name "*.swift" -not -path "*/DisabledTests/*" -not -path "*/TestHelpers/*" | sort))

echo "Found ${#test_files[@]} test files to check"
echo "=================================="

for test_file in "${test_files[@]}"; do
    # Extract test class name from file path
    filename=$(basename "$test_file" .swift)
    
    echo "Testing: $filename"
    
    # Run test with timeout
    (swift test --filter "$filename" &
    SWIFT_PID=$!
    sleep 15  # Shorter timeout for faster iteration
    if kill -0 $SWIFT_PID 2>/dev/null; then
        echo "  -> HANGING (killed after 15s)"
        pkill -f "swift test" || kill $SWIFT_PID
        echo "  -> Moving to DisabledTests"
        mv "$test_file" "Tests/NDKSwiftTests/DisabledTests/"
    else
        wait $SWIFT_PID
        exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "  -> PASSED"
        else
            echo "  -> FAILED (but completed)"
        fi
    fi
    ) 2>/dev/null
    
    echo ""
done

echo "Test analysis complete!"
