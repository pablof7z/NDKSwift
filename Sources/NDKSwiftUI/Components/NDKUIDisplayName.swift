import NDKSwiftCore
import SwiftUI

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

    @State private var profileDataSource: NDKProfileDataSource

    // MARK: - Supporting Types

    public enum FallbackStyle {
        case npub // Shows shortened npub (default)
        case placeholder // Shows "Unknown User"
        case pubkey // Shows shortened pubkey
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
        self.pubkey = pubkey
        self.fallbackStyle = fallbackStyle
        self._profileDataSource = State(wrappedValue: NDKProfileDataSource(
            ndk: ndk,
            pubkey: pubkey,
            maxAge: TimeConstants.hour
        ))
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
    }

    // MARK: - Public Properties

    /// The resolved display text for this user
    public var displayText: String {
        // If we have metadata, use the data source's display name logic
        if profileDataSource.metadata != nil {
            return profileDataSource.displayName
        }

        // Otherwise use custom fallback based on style
        return fallbackText
    }

    private var fallbackText: String {
        switch fallbackStyle {
        case .npub:
            if let npub = try? Bech32.npub(from: pubkey) {
                return String(npub.prefix(16)) + "..."
            }
            return String(pubkey.prefix(12)) + "..."
        case .placeholder:
            return "Unknown User"
        case .pubkey:
            return String(pubkey.prefix(16)) + "..."
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

// MARK: - Preview

#if DEBUG
    struct NDKUIDisplayName_Previews: PreviewProvider {
        static var previews: some View {
            // Create a mock NDK for preview
            let mockNDK = NDK(relayURLs: [])

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
                }
            }
            .padding()
        }
    }
#endif
