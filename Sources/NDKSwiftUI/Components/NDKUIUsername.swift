import NDKSwiftCore
import SwiftUI

/// Displays a Nostr username with NIP-05 support
///
/// This component shows a user's display name or NIP-05 identifier,
/// with automatic fallback to a truncated npub if no profile is available.
///
/// ## Usage
/// ```swift
/// NDKUIUsername(pubkey: userPubkey)
///     .font(.caption)
///     .foregroundStyle(.secondary)
/// ```
public struct NDKUIUsername: View {
    private let ndk: NDK
    private let pubkey: String
    private let maxLength: Int

    @StateObject private var profileState: ProfileState

    /// Initialize a username display component
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - pubkey: The user's public key (hex format)
    ///   - maxLength: Maximum length before truncation (default: 20)
    public init(ndk: NDK, pubkey: String, maxLength: Int = 20) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.maxLength = maxLength
        _profileState = StateObject(wrappedValue: ProfileState(pubkey: pubkey))
    }

    public var body: some View {
        Group {
            if let nip05 = profileState.nip05, !nip05.isEmpty {
                // Show NIP-05 identifier
                Text(formatNip05(nip05))
            } else if let name = profileState.name, !name.isEmpty {
                // Show display name
                Text(truncateIfNeeded(name))
            } else {
                // Fallback to truncated npub
                Text(truncatedNpub)
            }
        }
        .onAppear {
            Task {
                await profileState.loadProfile(profileManager: ndk.profileManager)
            }
        }
    }

    // MARK: - Private Helpers

    private func formatNip05(_ nip05: String) -> String {
        // Remove _@ prefix for root identifiers
        if nip05.hasPrefix("_@") {
            return String(nip05.dropFirst(2))
        }
        return truncateIfNeeded(nip05)
    }

    private func truncateIfNeeded(_ text: String) -> String {
        if text.count > maxLength {
            return String(text.prefix(maxLength - 3)) + "..."
        }
        return text
    }

    private var truncatedNpub: String {
        let npub = NDKUser(pubkey: pubkey).npub
        // Show first 8 and last 4 characters
        let prefix = String(npub.prefix(8))
        let suffix = String(npub.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - ProfileState

@MainActor
private class ProfileState: ObservableObject {
    @Published var name: String?
    @Published var nip05: String?

    private let pubkey: String
    private var loadTask: Task<Void, Never>?

    init(pubkey: String) {
        self.pubkey = pubkey
    }

    deinit {
        loadTask?.cancel()
    }

    func loadProfile(profileManager: NDKProfileManager) async {
        loadTask?.cancel()

        loadTask = Task {
            // Use profile manager to observe profile updates
            for await profile in await profileManager.subscribe(for: pubkey) {
                if !Task.isCancelled {
                    self.name = profile?.displayName ?? profile?.name
                    self.nip05 = profile?.nip05
                    break // Only need the first profile
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIUsername_Previews: PreviewProvider {
        static var previews: some View {
            // Create a mock NDK for preview
            let mockNDK = NDK(relayUrls: [])

            VStack(spacing: 16) {
                // With NIP-05
                NDKUIUsername(ndk: mockNDK, pubkey: "mock_pubkey_with_nip05")

                // With display name only
                NDKUIUsername(ndk: mockNDK, pubkey: "mock_pubkey_with_name")

                // Fallback to npub
                NDKUIUsername(ndk: mockNDK, pubkey: "mock_pubkey_no_profile")

                // Custom max length
                NDKUIUsername(ndk: mockNDK, pubkey: "mock_pubkey_long_name", maxLength: 15)
            }
            .padding()
        }
    }
#endif
