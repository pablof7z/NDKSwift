import Foundation
import NDKSwift

/// Example of a fully event-driven approach to Nutzap preferences
/// This shows how you could build a reactive system that responds to preference changes in real-time

// MARK: - Event-Driven Nutzap Manager

/// A manager that maintains live subscriptions to user preferences
/// and automatically updates when preferences change
actor EventDrivenNutzapManager {
    private let ndk: NDK
    private var preferenceSubscriptions: [String: NDKDataSource<NDKEvent>] = [:]
    private var cachedPreferences: [String: NDKNutzapPreferences] = [:]
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Subscribe to a user's nutzap preferences
    /// Returns an AsyncStream that emits preference updates
    func observePreferences(for user: NDKUser) -> AsyncStream<NDKNutzapPreferences?> {
        AsyncStream { continuation in
            Task {
                // Create filter for nutzap preferences
                var filter = NDKFilter()
                filter.authors = [user.pubkey]
                filter.kinds = [EventKind.nutzapPreferences]
                
                // Create data source with real-time updates (maxAge: 0)
                let dataSource = NDKDataSource(
                    ndk: ndk,
                    filter: filter,
                    maxAge: 0 // Keep subscription open for real-time updates
                )
                
                // Store the subscription
                preferenceSubscriptions[user.pubkey] = dataSource
                
                // Process events as they arrive
                for await event in dataSource.events {
                    let preferences = NDKNutzapPreferences(event: event)
                    cachedPreferences[user.pubkey] = preferences
                    continuation.yield(preferences)
                }
                
                // Clean up when done
                preferenceSubscriptions.removeValue(forKey: user.pubkey)
                cachedPreferences.removeValue(forKey: user.pubkey)
                continuation.finish()
            }
        }
    }
    
    /// Get current preferences (from cache if available)
    func getCurrentPreferences(for user: NDKUser) async -> NDKNutzapPreferences? {
        return cachedPreferences[user.pubkey]
    }
    
    /// Stop observing a user's preferences
    func stopObserving(user: NDKUser) async {
        preferenceSubscriptions.removeValue(forKey: user.pubkey)
    }
}

// MARK: - Usage Example

@main
struct EventDrivenExample {
    static func main() async throws {
        // Initialize NDK
        let ndk = NDK()
        try await ndk.connect()
        
        // Create event-driven manager
        let nutzapManager = EventDrivenNutzapManager(ndk: ndk)
        
        // Example user
        let user = NDKUser(pubkey: "example_pubkey")
        
        // Method 1: Subscribe to preference changes
        print("🔄 Starting live preference subscription...")
        
        Task {
            for await preferences in nutzapManager.observePreferences(for: user) {
                if let prefs = preferences {
                    print("📦 Preferences updated!")
                    print("   P2PK: \(await prefs.p2pkPubkey)")
                    print("   Mints: \(await prefs.mints.map { $0.url })")
                    
                    // React to changes - e.g., update UI, refresh wallet state
                    await handlePreferenceUpdate(prefs)
                }
            }
            print("🛑 Preference subscription ended")
        }
        
        // Method 2: One-shot fetch with event-driven approach
        await demonstrateOneShotFetch(ndk: ndk, user: user)
        
        // Keep running for demo
        try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
    }
    
    static func demonstrateOneShotFetch(ndk: NDK, user: NDKUser) async {
        print("\n🎯 One-shot preference fetch (event-driven)...")
        
        var filter = NDKFilter()
        filter.authors = [user.pubkey]
        filter.kinds = [EventKind.nutzapPreferences]
        
        // Use collect() to get all preference events until EOSE
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 300 // Cache for 5 minutes
        )
        
        // Method A: Get just the first (most recent) preference
        if let preferences = await dataSource.first(timeout: 5.0) {
            print("✅ Found preferences using first()")
            
        }
        
        // Method B: Collect all preference events (useful for history)
        let allPreferences = await dataSource.collect(timeout: 5.0)
        print("📊 Found \(allPreferences.count) preference events using collect()")
        
        // Method C: Process events as they arrive until EOSE
        print("\n🌊 Processing events as stream until EOSE...")
        for await event in dataSource.eventsUntilEOSE {
            print("   Got preference event: \(event.id)")
            // Process each event as it arrives
        }
        print("   Stream completed (EOSE received)")
    }
    
    static func handlePreferenceUpdate(_ preferences: NDKNutzapPreferences) async {
        // This would be called whenever preferences change
        // You could:
        // - Update UI
        // - Refresh wallet connections
        // - Clear outdated mint quotes
        // - Notify other parts of the app
        print("🔔 Handling preference update...")
    }
}

// MARK: - Alternative Pattern: Combine with SwiftUI

#if canImport(SwiftUI)
import SwiftUI
import Combine

/// SwiftUI-friendly wrapper using @Published
@MainActor
class NutzapPreferencesModel: ObservableObject {
    @Published var preferences: NDKNutzapPreferences?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let ndk: NDK
    private let user: NDKUser
    private var dataSource: NDKDataSource<NDKEvent>?
    private var task: Task<Void, Never>?
    
    init(ndk: NDK, user: NDKUser) {
        self.ndk = ndk
        self.user = user
        startObserving()
    }
    
    deinit {
        task?.cancel()
    }
    
    private func startObserving() {
        isLoading = true
        
        var filter = NDKFilter()
        filter.authors = [user.pubkey]
        filter.kinds = [EventKind.nutzapPreferences]
        
        // Create real-time subscription
        dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 0 // Real-time updates
        )
        
        // Process events
        task = Task { @MainActor [weak self] in
            guard let self = self, let dataSource = self.dataSource else { return }
            
            self.isLoading = false
            
            // React to each preference update
            for await event in dataSource.events {
                self.preferences = NDKNutzapPreferences(event: event)
            }
        }
    }
}

// SwiftUI View
struct NutzapPreferencesView: View {
    @StateObject private var model: NutzapPreferencesModel
    
    init(ndk: NDK, user: NDKUser) {
        _model = StateObject(wrappedValue: NutzapPreferencesModel(ndk: ndk, user: user))
    }
    
    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading preferences...")
            } else if let preferences = model.preferences {
                // UI automatically updates when preferences change
                PreferencesDetailView(preferences: preferences)
            } else {
                Text("No nutzap preferences found")
            }
        }
    }
}

struct PreferencesDetailView: View {
    let preferences: NDKNutzapPreferences
    @State private var mints: [NDKNutzapPreferences.MintInfo] = []
    
    var body: some View {
        List {
            Section("Mints") {
                ForEach(mints, id: \.url) { mint in
                    Text(mint.url.absoluteString)
                }
            }
        }
        .task {
            mints = await preferences.mints
        }
    }
}
#endif