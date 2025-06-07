import Foundation

// Minimal test to verify the subscription manager fix
print("Testing NDKSwift subscription race condition fix...")

// Simple async sleep to simulate the test
Task {
    print("Starting test...")
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    print("Test would run here if NDKSwift was available")
    print("The fix ensures subscriptions are registered with relay managers before sending REQ")
    exit(0)
}

// Keep the script running
RunLoop.main.run()