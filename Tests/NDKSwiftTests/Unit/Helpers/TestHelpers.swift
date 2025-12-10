import Foundation
import XCTest
@testable import NDKSwiftCore

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
    // Create a temporary NDK instance for building the event
    let ndk = NDK()
    
    // Build the event using NDKEventBuilder
    let builder = NDKEventBuilder(ndk: ndk)
        .kind(kind)
        .content(content)
    
    // Add tags
    for tag in tags {
        builder.tag(tag)
    }
    
    // Set pubkey if provided (otherwise will use signer's pubkey)
    if let pubkey = pubkey {
        // For test events without a signer, we need to build manually
        if signer == nil {
            let actualCreatedAt = createdAt ?? Timestamp.now
            let eventId = try calculateEventId(
                pubkey: pubkey,
                createdAt: actualCreatedAt,
                kind: kind,
                tags: tags,
                content: content
            )
            
            return NDKEvent(
                id: eventId,
                pubkey: pubkey,
                createdAt: actualCreatedAt,
                kind: kind,
                tags: tags,
                content: content,
                sig: "" // Unsigned event
            )
        }
    }
    
    // Build with signer if provided
    return try await builder.build(signer: signer)
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

/// Calculate event ID according to NIP-01
func calculateEventId(
    pubkey: PublicKey,
    createdAt: Timestamp,
    kind: Kind,
    tags: [Tag],
    content: String
) throws -> EventID {
    let serialized: [Any] = [
        0,
        pubkey,
        createdAt,
        kind,
        tags,
        content
    ]
    
    let jsonData = try JSONSerialization.data(withJSONObject: serialized, options: [])
    return Crypto.sha256(jsonData).hexEncodedString()
}

