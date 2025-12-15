//
// NDKSwiftTesting.swift
// NDKSwift
//
// Public test helpers for NDKSwift consumers.
//
// This module provides reusable test utilities for Nostr applications:
// - NDKEvent.test() - Create events with unique IDs (avoids deduplication issues)
// - TestKeyPairs - Deterministic test users (alice, bob, carol, dave, eve)
// - EventTestFactory - Factory methods for common event patterns
// - FilterTestFactory - Factory methods for creating filters
//
// Example:
// ```swift
// import NDKSwiftTesting
//
// func testMessageParsing() {
//     let event = NDKEvent.test(
//         kind: 1111,
//         content: "Hello",
//         tags: [["a", "project-ref"]],
//         pubkey: TestKeyPairs.alice.publicKey
//     )
//     let message = Message.from(event: event)
//     XCTAssertNotNil(message)
// }
// ```
//

// Re-export NDKSwiftCore for convenience
@_exported import NDKSwiftCore
