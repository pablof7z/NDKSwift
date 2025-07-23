import SwiftUI
import NDKSwift
import NDKSwiftUI

// MARK: - Example Usage

/// This example demonstrates how to use NDKSwiftUI components
@main
struct NDKSwiftUIExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var ndk: NDK?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("NDKSwiftUI Components")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                if let ndk = ndk {
                    ExampleComponentsView()
                        .environment(\.ndk, ndk)
                } else {
                    Text("Initializing NDK...")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .navigationTitle("NDKSwiftUI")
        }
        .task {
            await initializeNDK()
        }
    }
    
    private func initializeNDK() async {
        // Initialize with some default relays
        let relays = ["wss://relay.damus.io", "wss://relay.primal.net"]
        let ndkInstance = NDK(relayUrls: relays)
        await ndkInstance.connect()
        
        await MainActor.run {
            self.ndk = ndkInstance
        }
    }
}

struct ExampleComponentsView: View {
    // Example pubkey for demonstration
    private let examplePubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
    
    @StateObject private var profileDataSource: NDKProfileDataSource
    @StateObject private var eventDataSource: NDKEventDataSource
    @Environment(\.ndk) private var ndk
    
    init() {
        // Initialize with dummy NDK - will be updated with environment
        let dummyNDK = NDK(relayUrls: [])
        self._profileDataSource = StateObject(wrappedValue: NDKProfileDataSource(
            ndk: dummyNDK,
            pubkey: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        ))
        self._eventDataSource = StateObject(wrappedValue: NDKEventDataSource(
            ndk: dummyNDK,
            filter: NDKFilter(kinds: [1], limit: 10)
        ))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Profile Components Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile Components")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 16) {
                        // Profile pictures in different sizes
                        HStack(spacing: 16) {
                            NDKProfilePicture(pubkey: examplePubkey, size: 30)
                            NDKProfilePicture(pubkey: examplePubkey, size: 40)
                            NDKProfilePicture(pubkey: examplePubkey, size: 60)
                            NDKProfilePicture(pubkey: examplePubkey, size: 80)
                        }
                        
                        // Display names
                        VStack(alignment: .leading, spacing: 8) {
                            NDKDisplayName(pubkey: examplePubkey)
                                .font(.headline)
                            
                            NDKUsername(pubkey: examplePubkey)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Time Components Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time Components")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        NDKRelativeTime(timestamp: Timestamp(Date().timeIntervalSince1970 - 300))
                        NDKRelativeTime(timestamp: Timestamp(Date().timeIntervalSince1970 - 3600))
                        NDKRelativeTime(timestamp: Timestamp(Date().timeIntervalSince1970 - 86400))
                        
                        NDKRelativeTimeLong(timestamp: Timestamp(Date().timeIntervalSince1970 - 300))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Rich Text Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rich Text Components")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    NDKRichText(content: "Hello Nostr! Check out https://nostr.com and #bitcoin #nostr")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Event Components Section  
                VStack(alignment: .leading, spacing: 12) {
                    Text("Event Components")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Event components render different kinds of Nostr events:")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("• Kind 1: Text notes (Twitter-like)")
                        Text("• Kind 20: Picture events (Instagram-like, NIP-68)")
                        Text("• Kind 30023: Long-form articles (rich preview)")
                        Text("• Kind 9321: Cashu tokens")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Data Sources Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Sources")
                        .font(.title2)  
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Profile Loading:")
                            if profileDataSource.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(profileDataSource.profile?.name ?? "Not loaded")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Events Loaded:")
                            Text("\(eventDataSource.eventCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif