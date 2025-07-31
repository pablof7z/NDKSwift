#!/bin/bash

# Array of all remaining test files
TESTS=(
    "NDKSessionTests"
    "NDKSignerRegistryTests"
    "BlossomBlobTests"
    "BlossomClientMetadataTests"
    "BlossomMediaProcessorTests"
    "BlossomTypesTests"
    "NDKBlossomExtensionsTests"
    "NDKBlossomServerManagerTests"
    "EphemeralEventFilteringTests"
    "MemoryCacheTests"
    "NDKCacheProtocolTests"
    "ProfileSemanticCachingTests"
    "SQLiteCacheFilteringConsistencyTests"
    "SQLiteCacheMigrationTests"
    "NDKEventManagerTests"
    "NDKPoolTests"
    "NDKProfileManagerTests"
    "NDKRelayListManagerTests"
    "NDKSignatureVerificationCacheTests"
    "NDKTests"
    "CacheFirstTests"
    "CustomSubscriptionIdTests"
    "EOSECollectTests"
    "EventIDFilterOptimizationTests"
    "MultipleObserversTests"
    "SimpleObserverTests"
    "SubscriptionAggregationTests"
    "TagAggregationTests"
)

# Function to run a single test with timeout
run_test() {
    local test_name=$1
    echo "Testing $test_name..."
    
    # Run test with timeout
    timeout 25s swift test --filter "$test_name" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        echo "❌ TIMEOUT: $test_name (hangs)"
        echo "$test_name" >> hanging_tests.txt
        return 1
    elif [ $exit_code -ne 0 ]; then
        echo "❌ FAILED: $test_name"
        echo "$test_name" >> failed_tests.txt
        return 1
    else
        echo "✅ PASSED: $test_name"
        echo "$test_name" >> passed_tests.txt
        return 0
    fi
}

# Clear result files
> hanging_tests.txt
> failed_tests.txt
> passed_tests.txt

# Run first batch of tests
for test in "${TESTS[@]:0:10}"; do
    run_test "$test"
    sleep 1
done

echo "First batch complete. Check results in hanging_tests.txt, failed_tests.txt, passed_tests.txt"
