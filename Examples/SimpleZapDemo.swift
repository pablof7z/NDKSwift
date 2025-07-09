import Foundation
import NDKSwift

// Simple demo showing how to fetch and display zaps
@main
struct SimpleZapDemo {
    static func main() async {
        print("⚡ Simple Zap Viewing Demo")
        print("=========================\n")
        
        do {
            // Create NDK instance (no signer needed for just viewing)
            let ndk = NDK()
            
            // Add relays
            ndk.addRelay("wss://relay.damus.io")
            ndk.addRelay("wss://relay.nostr.band")
            
            // Connect
            print("📡 Connecting to relays...")
            await ndk.connect()
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Look up a popular user (jack dorsey)
            let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
            let jack = ndk.getUser(jackPubkey)
            
            // Fetch profile
            print("\n👤 Fetching user profile...")
            if let profile = try? await jack.fetchProfile() {
                print("User: \(profile.displayName ?? profile.name ?? "Unknown")")
                print("Bio: \(profile.about ?? "No bio")")
                print("Lightning: \(profile.lud16 ?? profile.lud06 ?? "Not configured")")
            }
            
            // Fetch recent zaps
            print("\n⚡ Recent zaps:")
            print("---------------")
            
            let zaps = try await jack.fetchZaps(includeNutzaps: true)
            
            if zaps.isEmpty {
                print("No zaps found")
            } else {
                // Show top 10 zaps
                for (index, zap) in zaps.prefix(10).enumerated() {
                    let typeEmoji = zap.type == ZapType.lightning ? "⚡" : "🥜"
                    let senderShort = zap.sender?.prefix(8) ?? "anonymous"
                    let timeAgo = formatTimeAgo(zap.timestamp)
                    
                    print("\n\(index + 1). \(typeEmoji) \(zap.amountSats) sats from \(senderShort)...")
                    print("   \(timeAgo)")
                    
                    if let comment = zap.comment, !comment.isEmpty {
                        print("   💬 \"\(comment)\"")
                    }
                }
                
                // Summary
                let totalSats = zaps.reduce(0) { $0 + $1.amountSats }
                let lightningCount = zaps.filter { $0.type == ZapType.lightning }.count
                let nutzapCount = zaps.filter { $0.type == ZapType.nutzap }.count
                
                print("\n📊 Summary:")
                print("   Total zaps: \(zaps.count)")
                print("   Lightning zaps: \(lightningCount)")
                print("   Nutzaps: \(nutzapCount)")
                print("   Total amount: \(totalSats) sats")
            }
            
            // Fetch zaps for a specific event
            print("\n\n📝 Fetching zaps for a recent note...")
            print("--------------------------------------")
            
            let noteFilter = NDKFilter(
                authors: [jackPubkey],
                kinds: [EventKind.textNote],
                limit: 5
            )
            
            let notes = try await ndk.fetchEvents(noteFilter)
            
            // Find a note with zaps
            for note in notes {
                let eventZaps = try await note.fetchZaps()
                if !eventZaps.isEmpty {
                    print("\nNote: \"\(note.content.prefix(100))...\"")
                    print("Zaps: \(eventZaps.count)")
                    print("Total: \(eventZaps.reduce(0) { $0 + $1.amountSats }) sats")
                    
                    // Show top 3 zaps
                    for (index, zap) in eventZaps.prefix(3).enumerated() {
                        let senderShort = zap.sender?.prefix(8) ?? "anon"
                        print("  \(index + 1). \(zap.amountSats) sats from \(senderShort)...")
                        if let comment = zap.comment {
                            print("     \"\(comment)\"")
                        }
                    }
                    break
                }
            }
            
            print("\n✅ Demo complete!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
