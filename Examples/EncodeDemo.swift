#!/usr/bin/env swift
import Foundation

// This would normally be:
// import NDKSwift
// But for this demo we'll show the usage

print("NDKSwift Event Encoding Demo")
print("===========================")

// Example usage of the new encode() method in NDKEvent

let examples = """

// Basic text note (kind 1) - encodes to note1
let textNote = NDKEvent(content: "Hello Nostr!")
textNote.kind = 1
textNote.pubkey = "abc123..."
try textNote.generateID()
let encoded = try textNote.encode()
// Result: note1abcd... (simple note encoding)

// Text note with metadata - encodes to nevent1 
let noteWithMentions = NDKEvent(content: "Hello @alice!")
noteWithMentions.addTag(["p", "alice_pubkey"])
let encodedWithMeta = try noteWithMentions.encode()
// Result: nevent1... (includes author, kind, relay hints)

// Replaceable event (kind 0 metadata) - encodes to naddr1
let metadata = NDKEvent(content: "{\\"name\\": \\"Alice\\"}")
metadata.kind = 0
metadata.pubkey = "alice_pubkey"
let encodedMeta = try metadata.encode()
// Result: naddr1... (includes kind, author)

// Parameterized replaceable event (kind 30023 article) - encodes to naddr1
let article = NDKEvent(content: "# My Article\\n\\nContent here...")
article.kind = 30023
article.addTag(["d", "my-article-slug"])
article.pubkey = "author_pubkey"
let encodedArticle = try article.encode()
// Result: naddr1... (includes identifier, kind, author)

// Include relay hints for better discoverability
let encodedWithRelays = try textNote.encode(includeRelays: true)
// Result: nevent1... (includes relay hints from NDK instance)

"""

print(examples)

print("Key Features:")
print("• Automatically chooses correct encoding type (note1/nevent1/naddr1)")
print("• Follows NIP-19 specification exactly")
print("• Supports relay hints for better event discovery")
print("• Handles replaceable and parameterized replaceable events")
print("• Compatible with ndk-core's event.encode() API")
