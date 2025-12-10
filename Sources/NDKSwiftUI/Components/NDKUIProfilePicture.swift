import SwiftUI
import NDKSwiftCore

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

    private let ndk: NDK
    private let pubkey: String
    private let size: CGFloat
    private let cornerRadius: CGFloat?
    private let borderColor: Color?
    private let borderWidth: CGFloat
    private var tapAction: (() -> Void)?

    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initialize with NDK instance and public key
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - pubkey: The user's public key (hex format)
    ///   - size: The size of the profile picture (default: 40)
    ///   - cornerRadius: Custom corner radius (default: circular)
    ///   - borderColor: Optional border color
    ///   - borderWidth: Border width (default: 0)
    public init(
        ndk: NDK,
        pubkey: String,
        size: CGFloat = 40,
        cornerRadius: CGFloat? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0
    ) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.size = size
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    /// Initialize with NDK instance and NDKUser
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - user: The NDKUser instance
    ///   - size: The size of the profile picture (default: 40)
    ///   - cornerRadius: Custom corner radius (default: circular)
    ///   - borderColor: Optional border color
    ///   - borderWidth: Border width (default: 0)
    public init(
        ndk: NDK,
        user: NDKUser,
        size: CGFloat = 40,
        cornerRadius: CGFloat? = nil,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 0
    ) {
        self.init(
            ndk: ndk,
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
                CachedAsyncImage(url: pictureURL) { image in
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
        .modifier(TapGestureModifier(tapAction: tapAction))
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
        guard let picture = metadata?.picture, !picture.isEmpty else { return nil }
        return URL(string: picture)
    }

    private var displayName: String {
        if let displayName = metadata?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let name = metadata?.name, !name.isEmpty {
            return name
        }
        // Fallback to shortened pubkey
        return String(pubkey.prefix(8)) + "..."
    }

    // MARK: - Private Methods

    private func loadProfile() {
        profileTask?.cancel()

        profileTask = Task {
            for await metadata in await ndk.profileManager.subscribe(for: pubkey) {
                await MainActor.run {
                    self.metadata = metadata
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

// MARK: - TapGestureModifier

/// A modifier that conditionally adds tap gesture handling only when a tap action is provided.
/// When no action is provided, the view passes through touches to parent views.
private struct TapGestureModifier: ViewModifier {
    let tapAction: (() -> Void)?

    func body(content: Content) -> some View {
        if let action = tapAction {
            content
                .contentShape(Circle())
                .onTapGesture { action() }
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIProfilePicture_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock NDK for preview
        let mockNDK = NDK(relayUrls: [])
        
        VStack(spacing: 20) {
            // Different sizes
            HStack(spacing: 16) {
                NDKUIProfilePicture(ndk: mockNDK, pubkey: "sample_pubkey", size: 30)
                NDKUIProfilePicture(ndk: mockNDK, pubkey: "sample_pubkey", size: UIConstants.ProfilePictureSize.small)
                NDKUIProfilePicture(ndk: mockNDK, pubkey: "sample_pubkey", size: UIConstants.ProfilePictureSize.medium)
                NDKUIProfilePicture(ndk: mockNDK, pubkey: "sample_pubkey", size: UIConstants.ProfilePictureSize.large)
            }

            // With border
            NDKUIProfilePicture(
                ndk: mockNDK,
                pubkey: "sample_pubkey",
                size: UIConstants.ProfilePictureSize.medium,
                borderColor: .blue,
                borderWidth: 2
            )

            // Square with custom corner radius
            NDKUIProfilePicture(
                ndk: mockNDK,
                pubkey: "sample_pubkey",
                size: UIConstants.ProfilePictureSize.medium,
                cornerRadius: 12
            )
        }
        .padding()
    }
}
#endif