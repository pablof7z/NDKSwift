//
// NDKEvent+Testing.swift
// NDKSwift
//
// Test helper extension for creating NDKEvent instances in unit tests.
//

import Foundation
import NDKSwiftCore

public extension NDKEvent {
    /// Create a test event with sensible defaults and unique ID
    ///
    /// Use this for unit tests instead of `NDKEvent.init()` to ensure
    /// each event has a unique ID for proper deduplication.
    ///
    /// Example:
    /// ```swift
    /// let event = NDKEvent.test(
    ///     kind: 1111,
    ///     content: "Hello",
    ///     tags: [["a", "project-ref"]],
    ///     pubkey: TestKeyPairs.alice.publicKey
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - kind: Event kind (default: 1 for text note)
    ///   - content: Event content (default: empty)
    ///   - tags: Event tags (default: empty)
    ///   - pubkey: Author's public key (default: alice's pubkey)
    ///   - createdAt: Timestamp (default: now)
    /// - Returns: A new NDKEvent with a unique ID
    static func test(
        kind: Kind = 1,
        content: String = "",
        tags: [[String]] = [],
        pubkey: String = TestKeyPairs.alice.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        NDKEvent(
            id: generateTestEventID(),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: generateTestSignature()
        )
    }

    /// Generate a unique test event ID (64 hex chars / 32 bytes)
    private static func generateTestEventID() -> String {
        // UUID is 32 hex chars, we need 64
        let uuid1 = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let uuid2 = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return uuid1 + uuid2
    }

    /// Generate a test signature (128 hex chars / 64 bytes)
    private static func generateTestSignature() -> String {
        return generateTestEventID() + generateTestEventID()
    }
}
