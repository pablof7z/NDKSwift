import SwiftUI
import NDKSwift

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

    private let pubkey: String
    private let fallbackStyle: FallbackStyle
    private var tapAction: (() -> Void)?

    @Environment(\.ndk) private var ndk
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?

    // MARK: - Supporting Types

    public enum FallbackStyle {
        case npub           // Shows shortened npub (default)
        case placeholder    // Shows "Unknown User"
        case pubkey         // Shows shortened pubkey
    }

    // MARK: - Initialization

    /// Initialize with a public key
    /// - Parameters:
    ///   - pubkey: The user's public key (hex format)
    ///   - fallbackStyle: How to display name when profile is unavailable
    public init(
        pubkey: String,
        fallbackStyle: FallbackStyle = .npub
    ) {
        self.pubkey = pubkey
        self.fallbackStyle = fallbackStyle
    }

    /// Initialize with an NDKUser
    /// - Parameters:
    ///   - user: The NDKUser instance
    ///   - fallbackStyle: How to display name when profile is unavailable
    public init(
        user: NDKUser,
        fallbackStyle: FallbackStyle = .npub
    ) {
        self.init(pubkey: user.pubkey, fallbackStyle: fallbackStyle)
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
        if let displayName = profile?.displayName,
           displayName.hasContent {
            return displayName
        }

        // Try regular name
        if let name = profile?.name,
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

        guard let ndk = ndk else { return }

        profileTask = Task {
            for await profile in await ndk.profileManager.observe(for: pubkey) {
                await MainActor.run {
                    self.profile = profile
                }
                // Continue listening for updates
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
        VStack(alignment: .leading, spacing: 16) {
            Group {
                // Different fallback styles
                NDKUIDisplayName(pubkey: "sample_pubkey", fallbackStyle: .npub)
                    .font(.headline)

                NDKUIDisplayName(pubkey: "sample_pubkey", fallbackStyle: .placeholder)
                    .font(.body)

                NDKUIDisplayName(pubkey: "sample_pubkey", fallbackStyle: .pubkey)
                    .font(.caption)

                Divider()

                // Username variant
                NDKUIUsername(pubkey: "sample_pubkey")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .environment(\.ndk, nil) // Mock environment
    }
}
#endif