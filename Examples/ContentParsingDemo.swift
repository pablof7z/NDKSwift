#!/usr/bin/env swift

import Foundation
import NDKSwift

// Demo: Content Parsing with NDKSwift
// This example shows how to parse Nostr content to identify and fetch referenced entities

@main
struct ContentParsingDemo {
    static func main() async {
        print("🎨 NDKSwift Content Parsing Demo")
        print("================================\n")
        
        // Initialize NDK with some relays
        let ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.nostr.band"
        ])
        
        // Connect to relays
        print("📡 Connecting to relays...")
        await ndk.connect()
        
        // Wait a moment for connections
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Example 1: Parse content without fetching
        await parseWithoutFetching(ndk: ndk)
        
        // Example 2: Parse content with entity fetching
        await parseWithFetching(ndk: ndk)
        
        // Example 3: Complex content parsing
        await parseComplexContent(ndk: ndk)
        
        // Disconnect
        await ndk.disconnect()
        print("\n✅ Demo completed!")
    }
    
    static func parseWithoutFetching(ndk: NDK) async {
        print("\n📝 Example 1: Parse without fetching")
        print("-----------------------------------")
        
        let content = "Hello @npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft! Check out #nostr at https://nostr.com"
        
        let options = ParseContentOptions(
            fetchUserProfiles: false,
            fetchReferencedEvents: false
        )
        
        do {
            let parsed = try await ndk.parseContent(content, options: options)
            
            print("Original: \(parsed.original)")
            print("\nSegments:")
            for (index, segment) in parsed.segments.enumerated() {
                print("  \(index): \(describeSegment(segment))")
            }
            
            print("\nGenerated tags:")
            for tag in parsed.tags {
                print("  \(tag)")
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    static func parseWithFetching(ndk: NDK) async {
        print("\n🔍 Example 2: Parse with entity fetching")
        print("---------------------------------------")
        
        let content = "Hey @npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft, what do you think about #bitcoin?"
        
        do {
            let parsed = try await ndk.parseContent(content)
            
            print("Parsing with profile fetch...")
            
            for segment in parsed.segments {
                switch segment {
                case .text(let text):
                    print(text, terminator: "")
                case .mention(let user):
                    let profile = await user.profile
                    let displayName = profile?.displayName ?? profile?.name ?? user.shortPubkey
                    print("@\(displayName)", terminator: "")
                case .hashtag(let tag):
                    print("#\(tag)", terminator: "")
                case .url(let url):
                    print(url.absoluteString, terminator: "")
                case .event:
                    break
                }
            }
            print()
        } catch {
            print("Error: \(error)")
        }
    }
    
    static func parseComplexContent(ndk: NDK) async {
        print("\n🎭 Example 3: Complex content parsing")
        print("------------------------------------")
        
        let content = """
        🚀 Just published a new article about @npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft's work on #nostr!
        
        Check it out at https://example.com/article
        
        Also see this event: nostr:note1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqpuy0p2x
        
        #bitcoin #decentralized #web3
        """
        
        do {
            let parsed = try await ndk.parseContent(content)
            
            // Count different segment types
            var textCount = 0
            var mentionCount = 0
            var eventCount = 0
            var hashtagCount = 0
            var urlCount = 0
            
            for segment in parsed.segments {
                switch segment {
                case .text: textCount += 1
                case .mention: mentionCount += 1
                case .event: eventCount += 1
                case .hashtag: hashtagCount += 1
                case .url: urlCount += 1
                }
            }
            
            print("Content analysis:")
            print("  Text segments: \(textCount)")
            print("  Mentions: \(mentionCount)")
            print("  Event references: \(eventCount)")
            print("  Hashtags: \(hashtagCount)")
            print("  URLs: \(urlCount)")
            print("  Total segments: \(parsed.segments.count)")
            
            // Show how to build UI from segments
            print("\nRendering example:")
            for segment in parsed.segments {
                await renderSegment(segment)
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    static func describeSegment(_ segment: ContentSegment) -> String {
        switch segment {
        case .text(let text):
            return "Text(\"\(text)\")"
        case .mention(let user):
            return "Mention(user: \(user.npub))"
        case .event(let event):
            return "Event(id: \(event.id))"
        case .hashtag(let tag):
            return "Hashtag(\(tag))"
        case .url(let url):
            return "URL(\(url.absoluteString))"
        }
    }
    
    static func renderSegment(_ segment: ContentSegment) async {
        switch segment {
        case .text(let text):
            // In a real app, this would be a Text view
            print(text, terminator: "")
            
        case .mention(let user):
            // In a real app, this would be a clickable mention view
            let profile = await user.profile
            let displayName = profile?.displayName ?? profile?.name ?? user.shortPubkey
            print("[@\(displayName)]", terminator: "")
            
        case .event(let event):
            // In a real app, this would be an embedded event preview
            let author = await event.author
            let authorName = await author.displayName ?? author.shortPubkey
            print("[Event by \(authorName)]", terminator: "")
            
        case .hashtag(let tag):
            // In a real app, this would be a clickable hashtag
            print("[#\(tag)]", terminator: "")
            
        case .url(let url):
            // In a real app, this would be a link preview
            print("[Link: \(url.host ?? url.absoluteString)]", terminator: "")
        }
    }
}