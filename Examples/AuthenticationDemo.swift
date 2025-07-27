#!/usr/bin/env swift

import Foundation
import NDKSwift

// MARK: - Authentication Demo

/// Example implementation of NDKAuthenticationDelegate
class MyAuthenticationDelegate: NDKAuthenticationDelegate {
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool {
        print("\n🔐 Relay \(relay.url) requires authentication")
        print("   Challenge: \(challenge)")
        
        // In a real app, you might:
        // 1. Show a dialog to the user
        // 2. Check if this relay is trusted
        // 3. Decide based on app policy
        
        // For this demo, we'll always authenticate
        print("   ✅ Proceeding with authentication...")
        return true
    }
}

// MARK: - Main Demo

@main
struct AuthenticationDemo {
    static func main() async {
        print("🚀 NDKSwift NIP-42 Authentication Demo")
        print("=====================================\n")
        
        do {
            // Create NDK instance with a signer
            let privateKey = try NDKPrivateKey.generate()
            let signer = NDKPrivateKeySigner(privateKey: privateKey)
            let ndk = NDK(signer: signer)
            
            // Set up authentication delegate
            let authDelegate = MyAuthenticationDelegate()
            ndk.authenticationDelegate = authDelegate
            
            print("📝 Created user with pubkey: \(try await signer.publicKey(for: .p256k1))")
            
            // Add a relay that requires authentication
            // Note: Replace with an actual auth-required relay URL
            let relayUrl = "wss://relay.example.com"
            let relay = try await ndk.addRelay(relayUrl)
            
            print("\n🔌 Connecting to relay: \(relayUrl)")
            
            // Monitor relay state changes
            Task {
                for await state in relay.stateStream {
                    print("   📡 Relay state: \(state.connectionState)")
                    
                    switch state.connectionState {
                    case .authRequired(let challenge):
                        print("   ⚠️  Authentication required with challenge: \(challenge)")
                    case .authenticating:
                        print("   🔄 Authenticating...")
                    case .authenticated:
                        print("   ✅ Successfully authenticated!")
                    case .failed(let error):
                        print("   ❌ Connection failed: \(error)")
                    default:
                        break
                    }
                }
            }
            
            // Try to connect
            do {
                try await relay.connect()
                print("✅ Connected to relay")
            } catch {
                print("❌ Failed to connect: \(error)")
            }
            
            // Wait a bit to see authentication flow
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Try to publish an event
            print("\n📤 Attempting to publish an event...")
            
            let event = try await NDKEventBuilder(ndk: ndk)
                .kind(.textNote)
                .content("Hello from NDKSwift with NIP-42 authentication!")
                .build(signer: signer)
            
            do {
                let publishedRelays = try await ndk.publish(event)
                print("✅ Event published to \(publishedRelays.count) relay(s)")
                
                // If the relay required auth and we weren't authenticated yet,
                // the publish might have failed initially, but after authentication
                // you can retry:
                if await relay.isAuthenticated {
                    print("🔐 Relay is authenticated, publish should succeed")
                }
            } catch {
                print("❌ Failed to publish: \(error)")
                
                // Check if we need to wait for authentication
                let relayState = await relay.connectionState
                if case .authRequired = relayState {
                    print("⏳ Waiting for authentication to complete...")
                    
                    // Wait for authentication
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                    
                    // Retry publish
                    if await relay.isAuthenticated {
                        print("🔄 Retrying publish after authentication...")
                        do {
                            let retryResult = try await ndk.publish(event)
                            print("✅ Retry successful! Published to \(retryResult.count) relay(s)")
                        } catch {
                            print("❌ Retry failed: \(error)")
                        }
                    }
                }
            }
            
            // Demonstrate checking relay authentication status
            print("\n📊 Relay Status:")
            print("   URL: \(relay.url)")
            print("   Connected: \(await relay.isConnected)")
            print("   Authenticated: \(await relay.isAuthenticated)")
            print("   State: \(await relay.connectionState)")
            
            // Clean up
            await relay.disconnect()
            print("\n👋 Demo completed!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension NDKRelayConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .authRequired(let challenge):
            return "authRequired(challenge: \(challenge.prefix(20))...)"
        case .authenticating:
            return "authenticating"
        case .authenticated:
            return "authenticated"
        case .disconnecting:
            return "disconnecting"
        case .failed(let error):
            return "failed(\(error))"
        }
    }
}