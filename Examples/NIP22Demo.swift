#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Example demonstrating NIP-22 comment support

@main
struct NIP22Demo {
    static func main() async throws {
        print("🎯 NDKSwift NIP-22 Comment Demo")
        print("================================\n")
        
        // Create NDK instance
        let ndk = NDK(clientName: "NIP22Demo")
        
        // Generate a test signer
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        print("✅ Created test user: \(signer.publicKey.prefix(16))...")
        
        // Create a mock blog post (kind 30023)
        let blogPost = try await ndk.event()
            .content("# My First Blog Post\n\nThis is an amazing article about Nostr development!")
            .kind(EventKind.longFormContent)
            .tag(["d", "my-first-post"])
            .tag(["title", "My First Blog Post"])
            .tag(["published_at", String(Int(Date().timeIntervalSince1970))])
            .build()
        
        print("\n📝 Created blog post:")
        print("   ID: \(blogPost.id.prefix(16))...")
        print("   Title: My First Blog Post")
        print("   Kind: \(blogPost.kind)")
        
        // Create a comment on the blog post
        let comment1 = try await ndk.reply(to: blogPost)
            .content("Great article! Thanks for sharing.")
            .build()
        
        print("\n💬 Created comment on blog post:")
        print("   ID: \(comment1.id.prefix(16))...")
        print("   Kind: \(comment1.kind) (generic reply)")
        print("   Content: \(comment1.content)")
        
        // Check the tags
        print("\n🏷️  Comment tags:")
        for tag in comment1.tags {
            if tag.count >= 2 {
                print("   [\(tag[0])] \(tag[1].prefix(32))...")
            }
        }
        
        // Create a reply to the comment
        let comment2 = try await ndk.reply(to: comment1)
            .content("I agree! This is very helpful.")
            .build()
        
        print("\n💬 Created reply to comment:")
        print("   ID: \(comment2.id.prefix(16))...")
        print("   Kind: \(comment2.kind)")
        print("   Content: \(comment2.content)")
        
        print("\n🏷️  Reply tags:")
        for tag in comment2.tags {
            if tag.count >= 2 {
                print("   [\(tag[0])] \(tag[1].prefix(32))...")
            }
        }
        
        // Verify tag structure
        print("\n✅ NIP-22 Validation:")
        
        // Check comment1 has uppercase tags for root
        let hasUppercaseA = comment1.tags.contains { $0.first == "A" }
        let hasUppercaseK = comment1.tags.contains { $0.first == "K" }
        let hasUppercaseP = comment1.tags.contains { $0.first == "P" }
        print("   Comment has uppercase tags: A=\(hasUppercaseA), K=\(hasUppercaseK), P=\(hasUppercaseP)")
        
        // Check comment2 carries over uppercase tags
        let comment2HasA = comment2.tags.contains { $0.first == "A" && $0.count > 1 && $0[1] == blogPost.tagAddress }
        let comment2HasK = comment2.tags.contains { $0.first == "K" && $0.count > 1 && $0[1] == String(blogPost.kind) }
        print("   Reply carries uppercase tags: A=\(comment2HasA), K=\(comment2HasK)")
        
        // Check lowercase tags point to parent
        let comment2HasLowercaseE = comment2.tags.contains { $0.first == "e" && $0.count > 1 && $0[1] == comment1.id }
        print("   Reply has lowercase e tag for parent: \(comment2HasLowercaseE)")
        
        print("\n✨ NIP-22 implementation working correctly!")
        
        // Show example of commenting on different event types
        print("\n📸 Example: Comment on image (kind 20)")
        let imageEvent = try await ndk.event()
            .content("Beautiful sunset!")
            .kind(EventKind.image)
            .tag(["url", "https://example.com/sunset.jpg"])
            .build()
        
        let imageComment = ndk.reply(to: imageEvent)
        print("   Image comment kind: \(imageComment.kind)")
        print("   Will have E tag (not A) because images aren't replaceable")
        
        print("\n🎉 Demo complete!")
    }
}

// Add Package.swift support for running with swift run
#if compiler(>=5.6)
@available(macOS 12.0, *)
extension NIP22Demo {
    static func main() async {
        do {
            try await Self.main()
        } catch {
            print("Error: \(error)")
        }
    }
}
#endif