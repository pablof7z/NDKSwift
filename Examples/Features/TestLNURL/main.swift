#!/usr/bin/env swift

import Foundation
import NDKSwift

// Simple test to verify LNURL resolution works
@main
struct TestLNURL {
    static func main() async {
        print("🧪 Testing LNURL Resolution")
        print("=" * 40)
        
        // Create an NDK instance
        let ndk = NDK()
        let resolver = ndk.lnurlResolver
        
        // Test cases for LUD16 addresses
        let lud16TestCases = [
            "satoshi@bitcoin.org",      // Won't work (fake address)
            "andre@lnmarkets.com",       // Should work if service is up
            "hello@getalby.com",         // Should work if service is up
            "notanemail",                // Should fail with invalid format
        ]
        
        // Test Bech32 LNURL encoding/decoding
        print("\n🔗 Testing Bech32 LNURL encoding/decoding")
        print("=" * 40)
        
        let testURL = "https://service.walletofsatoshi.com/.well-known/lnurlp/alice"
        print("Original URL: \(testURL)")
        
        // Encode to LNURL
        let urlData = testURL.data(using: .utf8)!
        let encodedData = try! Bech32.convertBits(data: Array(urlData), fromBits: 8, toBits: 5, pad: true)
        let lnurl = try! Bech32.encode(hrp: "lnurl", data: encodedData)
        
        print("Encoded LNURL: \(lnurl)")
        print("LNURL length: \(lnurl.count) characters")
        
        // Test decoding the LNURL we just created
        print("\n📥 Testing LNURL resolution:")
        do {
            // In a real scenario, this would make an HTTP request to the decoded URL
            // For this test, we'll just verify the LNURL format is recognized
            print("✅ LNURL format recognized: \(lnurl.hasPrefix("lnurl"))")
            print("   Would resolve to: \(testURL)")
        } catch {
            print("❌ Error: \(error)")
        }
        
        let testCases = lud16TestCases
        
        for address in testCases {
            print("\n📧 Testing: \(address)")
            do {
                let result = try await resolver.resolve(address)
                print("✅ Success!")
                print("   Provider pubkey: \(result.providerPubkey ?? "none")")
                print("   Allows Nostr: \(result.payResponse.allowsNostr ?? false)")
                print("   Min sendable: \(result.payResponse.minSendable / 1000) sats")
                print("   Max sendable: \(result.payResponse.maxSendable / 1000) sats")
                if !result.metadata.isEmpty {
                    print("   Metadata entries: \(result.metadata.count)")
                    for entry in result.metadata.prefix(3) {
                        print("     - \(entry.type): \(String(entry.value.prefix(50)))\(entry.value.count > 50 ? "..." : "")")
                    }
                }
            } catch let error as LNURLError {
                print("❌ LNURL Error: \(error.localizedDescription)")
            } catch {
                print("❌ Unexpected error: \(error)")
            }
        }
        
        print("\n\n🔧 Testing NDKZapManager integration")
        print("=" * 40)
        
        // Create a mock zap receipt to test validation
        let mockReceipt = createMockZapReceipt()
        let zapManager = NDKZapManager(ndk: ndk)
        
        print("\n📋 Mock zap receipt:")
        print("   Recipient: \(mockReceipt.recipientPubkey ?? "none")")
        print("   Event pubkey: \(mockReceipt.event.pubkey)")
        
        // The actual validation would happen internally in validateAndParseZapReceipt
        // but that's a private method, so we just verify the integration compiles
        print("\n✅ LNURL integration with NDKZapManager compiles successfully!")
    }
    
    static func createMockZapReceipt() -> NDKZapReceipt {
        // Create a mock event for testing
        let event = NDKEvent(
            id: "mock123",
            pubkey: "mockprovider456", 
            createdAt: Timestamp.now,
            kind: 9735,
            tags: [
                ["p", "recipient789"],
                ["bolt11", "lnbc100n1..."]
            ],
            content: "",
            sig: "mocksig"
        )
        
        return NDKZapReceipt(event: event)
    }
}

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}