#!/bin/bash

echo "Running NDKSwift Authentication Tests..."
echo "======================================="

# Run each auth test suite separately
echo -e "\n🧪 Running NDKSessionTests..."
swift test --filter "NDKSwiftTests.NDKSessionTests" 2>&1 | grep -E "Test Case|passed|failed|Executed" || echo "NDKSessionTests completed"

echo -e "\n🧪 Running NDKKeychainManagerTests..."
swift test --filter "NDKSwiftTests.NDKKeychainManagerTests" 2>&1 | grep -E "Test Case|passed|failed|Executed" || echo "NDKKeychainManagerTests completed"

echo -e "\n🧪 Running NDKSignerRegistryTests..."
swift test --filter "NDKSwiftTests.NDKSignerRegistryTests" 2>&1 | grep -E "Test Case|passed|failed|Executed" || echo "NDKSignerRegistryTests completed"

echo -e "\n🧪 Running NDKAuthManagerTests..."
swift test --filter "NDKSwiftTests.NDKAuthManagerTests" 2>&1 | grep -E "Test Case|passed|failed|Executed" || echo "NDKAuthManagerTests completed"

echo -e "\n✅ Authentication test run complete!"