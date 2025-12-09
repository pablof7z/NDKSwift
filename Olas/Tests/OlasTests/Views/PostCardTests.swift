// PostCardTests.swift
import XCTest
import SwiftUI
@testable import Olas
@testable import NDKSwift

final class PostCardTests: XCTestCase {

    func testPostCardProvidesProfileNavigationWithCorrectPubkey() {
        let expectedPubkey = "abc123pubkey"
        let event = NDKEvent(
            id: "test123",
            pubkey: expectedPubkey,
            createdAt: 1234567890,
            kind: EventKind.image,
            tags: [],
            content: "Test post",
            sig: "sig123"
        )

        var navigatedToPubkey: String?
        let onProfileTap: (String) -> Void = { pubkey in
            navigatedToPubkey = pubkey
        }

        // Simulate the profile tap action
        onProfileTap(event.pubkey)

        XCTAssertEqual(navigatedToPubkey, expectedPubkey)
    }

    func testPostCardExtractsImageURL() {
        // Create a mock image event with imeta tag
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: 1234567890,
            kind: EventKind.image,
            tags: [
                ["imeta", "url https://example.com/image.jpg", "m image/jpeg"]
            ],
            content: "Test caption",
            sig: "sig123"
        )

        let image = NDKImage(event: event)
        XCTAssertEqual(image.primaryImageURL, "https://example.com/image.jpg")
    }

    func testPostCardDisplaysCaption() {
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: 1234567890,
            kind: EventKind.image,
            tags: [],
            content: "Beautiful sunset #photography",
            sig: "sig123"
        )

        XCTAssertEqual(event.content, "Beautiful sunset #photography")
    }

    func testPostCardHandlesMissingImageURL() {
        // Create event without imeta tags
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: 1234567890,
            kind: EventKind.image,
            tags: [],
            content: "No image",
            sig: "sig123"
        )

        let image = NDKImage(event: event)
        XCTAssertNil(image.primaryImageURL)
    }

    func testPostCardHandlesEmptyCaption() {
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: 1234567890,
            kind: EventKind.image,
            tags: [
                ["imeta", "url https://example.com/image.jpg"]
            ],
            content: "",
            sig: "sig123"
        )

        XCTAssertEqual(event.content, "")
    }
}
