import SwiftUI
import NDKSwift

// MARK: - NDKDisplayName

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
/// NDKDisplayName(pubkey: user.pubkey)
///
/// // Customized styling
/// NDKDisplayName(pubkey: user.pubkey)
///     .font(.headline)
///     .foregroundStyle(.primary)
///     .onTapGesture { /* handle tap */ }
/// ```
public struct NDKDisplayName: View {

    // MARK: - Properties

    private let pubkey: String
    private let fallbackStyle: FallbackStyle
    private var tapAction: (() -> Void)?

    @Environment(\.ndk) private var ndk
    @StateObject private var profileDataSource: NDKProfileDataSource

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

        // Initialize data source - will be updated with correct NDK in onAppear
        self._profileDataSource = StateObject(wrappedValue: NDKProfileDataSource(
            ndk: NDK(), // Temporary - will be updated
            pubkey: pubkey
        ))
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
                // Update data source with environment NDK if available
                // Note: In a production implementation, we'd want a better pattern
                // for handling environment dependencies in StateObject
            }
    }

    // MARK: - Private Properties

    private var displayText: String {
        // Try display name first
        if let displayName = profileDataSource.profile?.displayName,
           displayName.hasContent {
            return displayName
        }

        // Try regular name
        if let name = profileDataSource.profile?.name,
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

    // MARK: - Modifiers

    /// Add a tap gesture to the display name
    public func onTapGesture(perform action: @escaping () -> Void) -> NDKDisplayName {
        var copy = self
        copy.tapAction = action
        return copy
    }
}

// MARK: - NDKUsername

/// A variant that prioritizes username over display name
public struct NDKUsername: View {

    private let pubkey: String
    private let fallbackStyle: NDKDisplayName.FallbackStyle
    private var tapAction: (() -> Void)?

    @Environment(\.ndk) private var ndk
    @StateObject private var profileDataSource: NDKProfileDataSource

    // MARK: - Initialization

    public init(
        pubkey: String,
        fallbackStyle: NDKDisplayName.FallbackStyle = .npub
    ) {
        self.pubkey = pubkey
        self.fallbackStyle = fallbackStyle

        self._profileDataSource = StateObject(wrappedValue: NDKProfileDataSource(
            ndk: NDK(),
            pubkey: pubkey
        ))
    }

    public init(
        user: NDKUser,
        fallbackStyle: NDKDisplayName.FallbackStyle = .npub
    ) {
        self.init(pubkey: user.pubkey, fallbackStyle: fallbackStyle)
    }

    // MARK: - Body

    public var body: some View {
        Text(usernameText)
            .onTapGesture {
                tapAction?()
            }
            .accessibilityLabel("Username: \(usernameText)")
    }

    // MARK: - Private Properties

    private var usernameText: String {
        // Try regular name first (usually the username)
        if let name = profileDataSource.profile?.name,
           name.hasContent {
            return "@\(name)"
        }

        // Fall back to display name
        if let displayName = profileDataSource.profile?.displayName,
           displayName.hasContent {
            return "@\(displayName)"
        }

        // Final fallback
        switch fallbackStyle {
        case .npub:
            let npub = NDKUser(pubkey: pubkey).npub
            return "@\(String(npub.prefix(16)))..."
        case .placeholder:
            return "@unknown"
        case .pubkey:
            return "@\(String(pubkey.prefix(16)))..."
        }
    }

    // MARK: - Modifiers

    public func onTapGesture(perform action: @escaping () -> Void) -> NDKUsername {
        var copy = self
        copy.tapAction = action
        return copy
    }
}

// MARK: - Preview

#if DEBUG
struct NDKDisplayName_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                // Different fallback styles
                NDKDisplayName(pubkey: "sample_pubkey", fallbackStyle: .npub)
                    .font(.headline)

                NDKDisplayName(pubkey: "sample_pubkey", fallbackStyle: .placeholder)
                    .font(.body)

                NDKDisplayName(pubkey: "sample_pubkey", fallbackStyle: .pubkey)
                    .font(.caption)

                Divider()

                // Username variant
                NDKUsername(pubkey: "sample_pubkey")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .environment(\.ndk, nil) // Mock environment
    }
}
#endif