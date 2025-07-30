import SwiftUI
import NDKSwift
import os.log

// MARK: - NDKUIDisplayName

/// A SwiftUI component that displays a user's display name with automatic profile loading.
///
/// The component features:
/// - Automatic profile loading from NDK data sources
/// - Intelligent fallback to name, then shortened npub
/// - Progressive loading (shows fallback immediately, updates when profile loads)
/// - Customizable styling
/// - Tap gesture support
///
/// ## Usage
///
/// ```swift
/// // Simple usage
/// NDKUIDisplayName(pubkey: user.pubkey)
///
/// // Customized styling
/// NDKUIDisplayName(pubkey: user.pubkey)
///     .font(.headline)
///     .foregroundStyle(.primary)
///     .onTapGesture { /* handle tap */ }
/// ```
public struct NDKUIDisplayName: View {

    // MARK: - Properties

    private let ndk: NDK
    private let pubkey: String
    private let fallbackStyle: FallbackStyle
    private var tapAction: (() -> Void)?

    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    // MARK: - Supporting Types

    public enum FallbackStyle {
        case npub           // Shows shortened npub (default)
        case placeholder    // Shows "Unknown User"
        case pubkey         // Shows shortened pubkey
    }

    // MARK: - Initialization

    /// Initialize with NDK instance and public key
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - pubkey: The user's public key (hex format)
    ///   - fallbackStyle: How to display name when profile is unavailable
    public init(
        ndk: NDK,
        pubkey: String,
        fallbackStyle: FallbackStyle = .npub
    ) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.fallbackStyle = fallbackStyle
    }

    /// Initialize with NDK instance and NDKUser
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - user: The NDKUser instance
    ///   - fallbackStyle: How to display name when profile is unavailable
    public init(
        ndk: NDK,
        user: NDKUser,
        fallbackStyle: FallbackStyle = .npub
    ) {
        self.init(ndk: ndk, pubkey: user.pubkey, fallbackStyle: fallbackStyle)
    }

    // MARK: - Body

    public var body: some View {
        Text(displayText)
            .onTapGesture {
                tapAction?()
            }
            .accessibilityLabel("User name: \(displayText)")
            .onAppear {
                loadProfile()
            }
            .onDisappear {
                profileTask?.cancel()
            }
            .onChange(of: pubkey) { _, newPubkey in
                loadProfile()
            }
    }

    // MARK: - Private Properties

    private var displayText: String {
        // Try display name first
        if let displayName = metadata?.displayName,
           displayName.hasContent {
            return displayName
        }

        // Try regular name
        if let name = metadata?.name,
           name.hasContent {
            return name
        }

        // Fall back based on style
        return fallbackText
    }

    private var fallbackText: String {
        switch fallbackStyle {
        case .npub:
            let npub = NDKUser(pubkey: pubkey).npub
            return String(npub.prefix(16)) + "..."
        case .placeholder:
            return "Unknown User"
        case .pubkey:
            return String(pubkey.prefix(16)) + "..."
        }
    }

    // MARK: - Private Methods

    private func loadProfile() {
        profileTask?.cancel()

        profileTask = Task {
            os_log(.debug, "NDKUIDisplayName: Starting profile observation for %{public}@", pubkey)
            var receivedProfile = false
            
            for await metadata in await ndk.profileManager.observe(for: pubkey) {
                receivedProfile = true
                os_log(.debug, "NDKUIDisplayName: Received metadata for %{public}@: %{public}@", pubkey, metadata?.displayName ?? metadata?.name ?? "<nil>")
                
                await MainActor.run {
                    self.metadata = metadata
                }
                // Continue listening for updates
            }
            
            if !receivedProfile {
                os_log(.debug, "NDKUIDisplayName: No profiles received for %{public}@", pubkey)
            }
        }
    }

    // MARK: - Modifiers

    /// Add a tap gesture to the display name
    public func onTapGesture(perform action: @escaping () -> Void) -> NDKUIDisplayName {
        var copy = self
        copy.tapAction = action
        return copy
    }
}

// MARK: - NDKUIUsername

// MARK: - Preview

#if DEBUG
struct NDKUIDisplayName_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock NDK for preview
        let mockNDK = NDK(relayUrls: [])
        
        VStack(alignment: .leading, spacing: 16) {
            Group {
                // Different fallback styles
                NDKUIDisplayName(
                    ndk: mockNDK,
                    pubkey: "sample_pubkey",
                    fallbackStyle: .npub
                )
                .font(.headline)

                NDKUIDisplayName(
                    ndk: mockNDK,
                    pubkey: "sample_pubkey",
                    fallbackStyle: .placeholder
                )
                .font(.body)

                NDKUIDisplayName(
                    ndk: mockNDK,
                    pubkey: "sample_pubkey",
                    fallbackStyle: .pubkey
                )
                .font(.caption)

                Divider()

                // Username variant would need similar update
                Text("NDKUIUsername needs update")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
#endif