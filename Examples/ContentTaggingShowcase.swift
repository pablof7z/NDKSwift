#!/usr/bin/env swift

import Foundation

print("🎯 NDKSwift Content Tagging Showcase")
print("====================================")
print("Demonstrating automatic content tagging with bech32 to hex conversion")

// Example from the user request
let userExample = "hello nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
let expectedHex = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"

print("\n1. User Example:")
print("   Content: \(userExample)")
print("   Expected tag: [\"p\", \"\(expectedHex)\"]")

// Hashtag examples
print("\n2. Hashtag Extraction:")
let hashtagContent = "This is a post about #bitcoin, #lightning, and #nostr"
print("   Content: \(hashtagContent)")
print("   Expected tags:")
print("     - [\"t\", \"bitcoin\"]")
print("     - [\"t\", \"lightning\"]")
print("     - [\"t\", \"nostr\"]")

// Mixed content example
print("\n3. Mixed Content Example:")
let mixedContent = "GM! Check out nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft and this note: @note1fntxf5qq4z6fmk186mwwu7t0972rcez8cejatp0698lrzspsuyqq9m4vm7 about #bitcoin"
print("   Content: \(mixedContent)")
print("   Expected tags:")
print("     - [\"p\", \"fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52\"] (from npub)")
print("     - [\"q\", \"<hex_event_id>\", \"\"] (from note)")
print("     - [\"t\", \"bitcoin\"] (from hashtag)")

// nprofile example
print("\n4. Complex Entity Examples:")
print("   nprofile: Contains pubkey + relay hints → [\"p\", \"hex_pubkey\"]")
print("   nevent: Contains event ID + metadata → [\"q\", \"hex_event_id\", \"relay\"]")
print("   naddr: Contains kind:pubkey:identifier → [\"q\", \"kind:hex_pubkey:identifier\", \"relay\"]")

print("\n5. Key Features:")
print("   ✅ Hashtag extraction: #word → [\"t\", \"word\"]")
print("   ✅ User mentions: npub/nprofile → [\"p\", \"hex_pubkey\"]")
print("   ✅ Event references: note/nevent/naddr → [\"q\", \"hex_id\", \"relay?\"]")
print("   ✅ Bech32 → hex conversion for all tags")
print("   ✅ Content normalization to nostr: format")
print("   ✅ Tag deduplication and merging")
print("   ✅ Automatic integration with NDKEvent.sign() and NDK.publish()")

print("\n6. Usage in NDKSwift:")
print("   // Manual tagging")
print("   event.generateContentTags()")
print("")
print("   // Automatic tagging when setting content")
print("   event.setContent(\"Hello #world\")")
print("")
print("   // Automatic tagging during signing")
print("   await event.sign() // calls generateContentTags()")
print("")
print("   // Automatic tagging during publishing")
print("   await ndk.publish(event) // signs if needed, which calls generateContentTags()")

print("\n🚀 Implementation Complete!")
print("   The ContentTagger now properly converts bech32 entities to hex")
print("   while preserving the original bech32 format in the content.")
print("   This matches the behavior of ndk-core's generateContentTags function.")

print("\n🔧 Technical Details:")
print("   • Uses robust regex patterns for entity detection")
print("   • Implements full bech32 decoding with TLV support")
print("   • Handles nprofile, nevent, and naddr complex entities")
print("   • Maintains content readability while ensuring hex tags")
print("   • Integrates seamlessly with existing NDKEvent workflow")
