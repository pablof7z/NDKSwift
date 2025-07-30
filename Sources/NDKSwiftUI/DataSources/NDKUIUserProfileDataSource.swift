import Foundation
import NDKSwift
import SwiftUI
import Combine

// MARK: - User Profile Data Source

/// Data source for user profile metadata
@MainActor
public class NDKUIUserProfileDataSource: ObservableObject {
    @Published public private(set) var metadata: NDKUserMetadata?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let ndk: NDK
    private let pubkey: String
    private var profileTask: Task<Void, Never>?
    
    public init(ndk: NDK, pubkey: String) {
        self.ndk = ndk
        self.pubkey = pubkey
        
        // Start observing immediately
        profileTask = Task {
            await observeProfile()
        }
    }
    
    deinit {
        profileTask?.cancel()
    }
    
    private func observeProfile() async {
        // Use NDKProfileManager for best practices
        for await metadataUpdate in await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
            await MainActor.run {
                self.metadata = metadataUpdate
                self.isLoading = false
            }
        }
    }
}