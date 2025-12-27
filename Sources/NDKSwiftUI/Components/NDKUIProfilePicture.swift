import Kingfisher
import NDKSwiftCore
import SwiftUI

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
@MainActor
public struct NDKUIProfilePicture: View {
    // MARK: - Properties

    private let ndk: NDK
    private let pubkey: String
    private let size: CGFloat
    private let cornerRadius: CGFloat?
    private let borderColor: Color?
    private let borderWidth: CGFloat
    private var tapAction: (() -> Void)?

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?

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

    // MARK: - Body

    public var body: some View {
        Group {
            if let pictureURL = profile?.pictureURL {
                KFImage(pictureURL)
                    .resizable()
                    .placeholder { placeholderView }
                    .aspectRatio(contentMode: .fill)
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
        .accessibilityLabel("Profile picture for \(profile?.displayName ?? "user")")
        .task {
            // Load profile and hold reference so SwiftUI observes changes
            profile = ndk.profile(for: pubkey)
        }
    }

    // MARK: - Private Views

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: effectiveCornerRadius)
            .fill(Color.ndkGray5)
            .frame(width: size, height: size)
            .overlay(
                Text((profile?.displayName ?? "?").prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var effectiveCornerRadius: CGFloat {
        cornerRadius ?? (size / 2) // Default to circular
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
            let mockNDK = NDK(relayURLs: [])

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
