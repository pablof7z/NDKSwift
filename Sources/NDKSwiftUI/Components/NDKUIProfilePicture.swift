import SwiftUI
import NDKSwift

#if canImport(UIKit)
import UIKit
#endif

// MARK: - NDKUIProfilePicture

/// A SwiftUI component that displays a user's profile picture with automatic loading and fallbacks.
///
/// The component features:
/// - Automatic profile loading from NDK data sources
/// - Responsive image loading with AsyncImage
/// - Customizable size and styling
/// - Progressive loading (shows fallback immediately, updates when profile loads)
/// - Tap gesture support
/// - Accessibility support
///
/// ## Usage
///
/// ```swift
/// // Simple usage
/// NDKUIProfilePicture(pubkey: user.pubkey)
///
/// // Customized
/// NDKUIProfilePicture(pubkey: user.pubkey)
///     .frame(width: 80, height: 80)
///     .onTapGesture { /* handle tap */ }
/// ```
public struct NDKUIProfilePicture: View {

    // MARK: - Properties

    private let pubkey: String
    private let size: CGFloat
    private let cornerRadius: CGFloat?
    private let borderColor: Color?
    private let borderWidth: CGFloat
    private var tapAction: (() -> Void)?

    @Environment(\.ndk) private var ndk
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initialize with a public key
    /// - Parameters:
    ///   - pubkey: The user's public key (hex format)
    ///   - size: The size of the profile picture (default: 40)
    ///   - cornerRadius: Custom corner radius (default: circular)
    ///   - borderColor: Optional border color
    ///   - borderWidth: Border width (default: 0)
    public init(
        pubkey: String,
        size: CGFloat = 40,
        cornerRadius: CGFloat? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0
    ) {
        self.pubkey = pubkey
        self.size = size
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth

        // Profile will be loaded in onAppear when we have access to the environment NDK
    }

    /// Initialize with an NDKUser
    /// - Parameters:
    ///   - user: The NDKUser instance
    ///   - size: The size of the profile picture (default: 40)
    ///   - cornerRadius: Custom corner radius (default: circular)
    ///   - borderColor: Optional border color
    ///   - borderWidth: Border width (default: 0)
    public init(
        user: NDKUser,
        size: CGFloat = 40,
        cornerRadius: CGFloat? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0
    ) {
        self.init(
            pubkey: user.pubkey,
            size: size,
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth
        )
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let pictureURL = pictureURL {
                AsyncImage(url: pictureURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderView
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: effectiveCornerRadius))
            } else {
                placeholderView
            }
        }
        .overlay(
            // Border overlay
            RoundedRectangle(cornerRadius: effectiveCornerRadius)
                .stroke(borderColor ?? Color.clear, lineWidth: borderWidth)
        )
        .onTapGesture {
            tapAction?()
        }
        .accessibilityLabel("Profile picture for \(displayName)")
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

    // MARK: - Private Views

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: effectiveCornerRadius)
            .fill(Color.ndkGray5)
            .frame(width: size, height: size)
            .overlay(
                Text(displayName.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var effectiveCornerRadius: CGFloat {
        cornerRadius ?? (size / 2) // Default to circular
    }

    private var pictureURL: URL? {
        guard let picture = profile?.picture, !picture.isEmpty else { return nil }
        return URL(string: picture)
    }

    private var displayName: String {
        if let displayName = profile?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let name = profile?.name, !name.isEmpty {
            return name
        }
        // Fallback to shortened pubkey
        return String(pubkey.prefix(8)) + "..."
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

    /// Add a tap gesture to the profile picture
    public func onTapGesture(perform action: @escaping () -> Void) -> NDKUIProfilePicture {
        var copy = self
        copy.tapAction = action
        return copy
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIProfilePicture_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Different sizes
            HStack(spacing: 16) {
                NDKUIProfilePicture(pubkey: "sample_pubkey", size: 30)
                NDKUIProfilePicture(pubkey: "sample_pubkey", size: UIConstants.ProfilePictureSize.small)
                NDKUIProfilePicture(pubkey: "sample_pubkey", size: UIConstants.ProfilePictureSize.medium)
                NDKUIProfilePicture(pubkey: "sample_pubkey", size: UIConstants.ProfilePictureSize.large)
            }

            // With border
            NDKUIProfilePicture(
                pubkey: "sample_pubkey",
                size: UIConstants.ProfilePictureSize.medium,
                borderColor: .blue,
                borderWidth: 2
            )

            // Square with custom corner radius
            NDKUIProfilePicture(
                pubkey: "sample_pubkey",
                size: UIConstants.ProfilePictureSize.medium,
                cornerRadius: 12
            )
        }
        .padding()
        .environment(\.ndk, nil) // Mock environment
    }
}
#endif