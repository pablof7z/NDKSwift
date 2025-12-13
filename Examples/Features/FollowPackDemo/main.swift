#!/usr/bin/env swift
import Foundation
import NDKSwift

/// This example demonstrates how to use NDKFollowPack to create, manage, and fetch follow packs.
/// Follow packs are collections of pubkeys with metadata like title, description, and image.

// MARK: - Setup

print("🚀 Starting Follow Pack Demo...")

// Initialize NDK
let ndk = NDK()

// Configure signer (replace with your actual private key)
let privateKey = ProcessInfo.processInfo.environment["NOSTR_PRIVATE_KEY"] ?? "test_private_key_64_chars_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
let signer = try NDKPrivateKeySigner(privateKey: privateKey)
ndk.signer = signer

// Add relays
ndk.relayPool.addRelay(url: RelayConstants.damus)
ndk.relayPool.addRelay(url: RelayConstants.nosLol)
ndk.relayPool.addRelay(url: RelayConstants.primal)

// Connect to relays
print("🔌 Connecting to relays...")
try await ndk.connect()

// MARK: - Creating a Follow Pack

print("\n📦 Creating a new follow pack...")

// Create and publish a follow pack using the builder pattern
let followPack = try await NDKFollowPackBuilder(ndk: ndk)
    .title("Bitcoin Developers")
    .description("A curated list of Bitcoin Core developers and contributors")
    .identifier("bitcoin-devs-\(Timestamp.now)")
    .pubkeys([
        "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
        "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
        "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245", // jb55
    ])
    .image(NDKImetaTag(
        url: "https://example.com/bitcoin-devs.jpg",
        alt: "Bitcoin Developers Logo",
        dim: "400x400"
    ))
    .publish()

print("✅ Published with ID: \(followPack.event.id)")

// MARK: - Creating a Media Follow Pack

print("\n🎨 Creating a media follow pack...")

// Create a media-focused follow pack
let mediaFollowPack = try await NDKFollowPackBuilder(ndk: ndk)
    .kind(EventKind.mediaFollowPack) // Kind 39092 for media-focused packs
    .title("Nostr Photography")
    .description("Amazing photographers sharing their work on Nostr")
    .identifier("nostr-photography")
    .image("https://example.com/photography-pack.jpg") // Simple image URL
    .addPubkey("npub1234...") // Example photographer 1
    .addPubkey("npub5678...") // Example photographer 2
    .publish()

print("✅ Published media follow pack")

// MARK: - Observing Follow Packs

print("\n🔍 Observing follow packs...")

// Observe all follow packs from the current user
let userFilter = NDKFilter(
    authors: [signer.publicKey],
    kinds: NDKFollowPack.supportedKinds
)
let userPacksObserver = ndk.subscribe(filter: userFilter)

print("📦 Follow packs by current user:")
var userPacks: [NDKFollowPack] = []
for await event in userPacksObserver.events {
    let pack = NDKFollowPack(event: event, ndk: ndk)
    userPacks.append(pack)
    print("  - \(pack.title ?? "Untitled") (\(pack.pubkeys.count) pubkeys)")

    // For demo purposes, break after getting a few
    if userPacks.count >= 5 {
        break
    }
}

// Observe a specific follow pack by identifier
let specificFilter = NDKFilter(
    authors: [signer.publicKey],
    kinds: NDKFollowPack.supportedKinds,
    tags: ["d": Set(["bitcoin-devs"])]
)
let specificObserver = ndk.subscribe(filter: specificFilter)

for await event in specificObserver.events {
    let fetchedPack = NDKFollowPack(event: event, ndk: ndk)
    print("\n📦 Found specific pack: \(fetchedPack.title ?? "Untitled")")
    print("   Description: \(fetchedPack.description ?? "No description")")
    print("   Contains \(fetchedPack.pubkeys.count) pubkeys")
    break // Just get the first one
}

// Observe all follow packs (with limit)
let allFilter = NDKFilter(kinds: NDKFollowPack.supportedKinds, limit: 10)
let allPacksObserver = ndk.subscribe(filter: allFilter)

print("\n📦 Recent follow packs:")
var allPacks: [NDKFollowPack] = []
for await event in allPacksObserver.events {
    let pack = NDKFollowPack(event: event, ndk: ndk)
    allPacks.append(pack)

    if allPacks.count >= 10 {
        break
    }
}

print("Found \(allPacks.count) follow packs")

// MARK: - Managing Follow Pack Contents

print("\n✏️ Managing follow pack contents...")

// Demonstrate how to work with existing follow packs
if let existingPack = allPacks.first {
    print("Found pack: \(existingPack.title ?? "Untitled")")

    // Check if pack contains a specific pubkey
    let containsJack = existingPack.containsPubkey("82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
    print("Contains jack: \(containsJack)")

    // To update a pack, create a new version with modified content
    let updatedPack = try await ndk.followPack()
        .title("\(existingPack.title ?? "") - Updated")
        .description(existingPack.description ?? "")
        .identifier(existingPack.identifier ?? "updated-pack")
        .pubkeys(existingPack.pubkeys + ["newpubkey123..."]) // Add new pubkey
        .publish()

    print("✅ Published updated pack")
}

// MARK: - Converting Between Events and Follow Packs

print("\n🔄 Converting between events and follow packs...")

// Access the underlying event
let event = followPack.event
print("📋 Event kind: \(event.kind), ID: \(event.id)")

// Convert event back to follow pack
let reconstructedPack = NDKFollowPack.from(event: event, ndk: ndk)
print("📦 Reconstructed pack: \(reconstructedPack.title ?? "Untitled")")

// MARK: - Advanced Usage

print("\n🎯 Advanced usage examples...")

// Create a follow pack with complex metadata
let advancedPack = try await NDKFollowPackBuilder(ndk: ndk)
    .title("Nostr Protocol Developers")
    .description("""
    Core developers and contributors to the Nostr protocol.
    This list includes NIP authors and implementers.
    """)
    .identifier("nostr-protocol-devs")
    .image(NDKImetaTag(
        url: "https://primary.com/image.jpg",
        blurhash: "LEHV6nWB2yk8pyoJadR*.7kCMdnj",
        dim: "800x600",
        alt: "Nostr Protocol Developers",
        fallback: [
            "https://backup1.com/image.jpg",
            "https://backup2.com/image.jpg",
        ]
    ))
    .pubkeys([
        "valid_64_char_hex_pubkey_1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "valid_64_char_hex_pubkey_2_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ])
    .build() // Just build, don't publish

print("📦 Created advanced pack with:")
print("   - Rich image metadata including blurhash")
print("   - Fallback image URLs")
print("   - \(advancedPack.pubkeys.count) validated pubkeys")

// MARK: - Cleanup

print("\n🧹 Disconnecting...")
await ndk.disconnect()
print("✅ Follow Pack Demo completed!")

// Note: In a real application, you would:
// 1. Use actual pubkeys of users you want to include
// 2. Store follow pack identifiers for later retrieval
// 3. Implement UI for users to create and manage their packs
// 4. Handle errors appropriately
// 5. Consider caching follow packs locally
