import Foundation
import XCTest
@testable import NDKSwift

// MARK: - Common Test Helpers

/// Formats current time as HH:mm:ss.SSS for test logging
func timestamp() -> String {
    return DateFormatters.custom(format: "HH:mm:ss.SSS").string(from: Date())
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
let testRelays = RelayConstants.testRelays

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

// MARK: - Test Event Creation

/// Creates a test event with common defaults
/// - Parameters:
///   - kind: The event kind (default: 1)
///   - content: The event content
///   - tags: Event tags
///   - pubkey: Optional pubkey (generates random if not provided)
///   - createdAt: Optional timestamp (uses current time if not provided)
///   - signer: Optional signer for the event
/// - Returns: A signed or unsigned NDKEvent
func createTestEvent(
    kind: Kind = 1,
    content: String = "Test event",
    tags: [Tag] = [],
    pubkey: String? = nil,
    createdAt: Timestamp? = nil,
    signer: NDKSigner? = nil
) async throws -> NDKEvent {
    let actualPubkey = pubkey ?? try generateRandomHex(32)
    let actualCreatedAt = createdAt ?? Timestamp(Date().timeIntervalSince1970)
    
    let event = NDKEvent(
        pubkey: actualPubkey,
        kind: kind,
        content: content,
        tags: tags,
        createdAt: actualCreatedAt
    )
    
    if let signer = signer {
        _ = try await event.sign(with: signer)
    }
    
    return event
}

/// Generates a random hex string of specified byte length
func generateRandomHex(_ byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let result = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    guard result == errSecSuccess else {
        throw TestError.invalidResponse("Failed to generate random bytes")
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
}

