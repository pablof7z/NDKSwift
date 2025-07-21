import Foundation
import XCTest
@testable import NDKSwift

// MARK: - Common Test Helpers

/// Formats current time as HH:mm:ss.SSS for test logging
func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

/// Creates a delay for the specified number of seconds
func delay(_ seconds: TimeInterval) async throws {
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

/// Waits for a condition to become true with timeout
func waitFor(
    timeout: TimeInterval = 10.0,
    interval: TimeInterval = 0.1,
    condition: () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    
    while Date() < deadline {
        if await condition() {
            return
        }
        try await delay(interval)
    }
    
    throw TestError.timeout("Condition not met within \(timeout) seconds")
}

/// Common test errors
enum TestError: LocalizedError {
    case timeout(String)
    case connectionFailed
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .timeout(let message):
            return "Timeout: \(message)"
        case .connectionFailed:
            return "Failed to connect to relays"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        }
    }
}

/// Test relay URLs commonly used across E2E tests
let testRelays = [
    "wss://relay.damus.io",
    "wss://relay.nostr.band", 
    "wss://nos.lol"
]

/// Creates test users with signers
struct TestUser {
    let signer: NDKPrivateKeySigner
    let pubkey: String
    
    static func create() async throws -> TestUser {
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        return TestUser(signer: signer, pubkey: pubkey)
    }
}

