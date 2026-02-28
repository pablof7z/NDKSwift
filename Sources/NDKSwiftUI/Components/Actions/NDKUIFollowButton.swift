import NDKSwiftCore
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - NDKUIFollowButton

/// A button component for following/unfollowing Nostr users with contact list management.
///
/// Features:
/// - Follow/unfollow toggle states
/// - Contact list integration (kind:3 events)
/// - Real-time follow status updates
/// - Customizable button styles
/// - Loading and confirmation states
/// - Batch contact list updates
/// - Haptic feedback
///
/// ## Usage
///
/// ```swift
/// // Basic follow button
/// NDKUIFollowButton(ndk: ndk, pubkey: user.pubkey)
///     .onFollowChanged { isFollowing in
///         print("User is \(isFollowing ? "followed" : "unfollowed")")
///     }
///
/// // Custom styling
/// NDKUIFollowButton(ndk: ndk, pubkey: user.pubkey, style: .compact, showFollowText: false)
/// ```
public struct NDKUIFollowButton: View {
    // MARK: - Properties

    private let ndk: NDK
    private let pubkey: String
    private let style: ButtonStyle
    private let showFollowText: Bool
    private let confirmUnfollow: Bool
    private var onFollowChanged: ((Bool) -> Void)?

    @StateObject private var followState: FollowState
    @State private var showUnfollowConfirmation = false

    // MARK: - Supporting Types

    public enum ButtonStyle {
        case standard // Full button with text
        case compact // Icon-based button
        case minimal // Text-only button
    }

    // MARK: - Initialization

    /// Initialize a follow button
    /// - Parameters:
    ///   - ndk: The NDK instance to use for operations
    ///   - pubkey: The public key of the user to follow/unfollow
    ///   - style: Button presentation style
    ///   - showFollowText: Whether to show "Follow"/"Following" text
    ///   - confirmUnfollow: Whether to show confirmation before unfollowing
    public init(
        ndk: NDK,
        pubkey: String,
        style: ButtonStyle = .standard,
        showFollowText: Bool = true,
        confirmUnfollow: Bool = true
    ) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.style = style
        self.showFollowText = showFollowText
        self.confirmUnfollow = confirmUnfollow

        // Initialize follow state
        _followState = StateObject(wrappedValue: FollowState(targetPubkey: pubkey))
    }

    // MARK: - Body

    public var body: some View {
        Button(action: handleFollowTap) {
            HStack(spacing: buttonSpacing) {
                // Icon
                Image(systemName: followState.isFollowing ? "person.fill.checkmark" : "person.badge.plus")
                    .font(iconFont)
                    .foregroundStyle(iconColor)

                // Text (if enabled)
                if showFollowText {
                    Text(followState.isFollowing ? "Following" : "Follow")
                        .font(textFont)
                        .fontWeight(.medium)
                        .foregroundStyle(textColor)
                }

                // Loading indicator
                if followState.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(buttonPadding)
            .background(backgroundColor)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(followState.isLoading || ndk.signer == nil)
        .opacity(followState.isLoading ? OpacityConstants.overlay : 1.0)
        .confirmationDialog(
            "Unfollow User",
            isPresented: $showUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                executeUnfollow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to unfollow this user?")
        }
        .onAppear {
            setupFollowObservation()
        }
    }

    // MARK: - Private Methods

    private func handleFollowTap() {
        if followState.isFollowing && confirmUnfollow {
            showUnfollowConfirmation = true
        } else {
            executeToggleFollow()
        }

        // Haptic feedback
        #if canImport(UIKit)
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        #endif
    }

    private func executeUnfollow() {
        Task {
            await followState.unfollowUser(ndk: ndk)
            onFollowChanged?(followState.isFollowing)

            // Success haptic
            #if canImport(UIKit)
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
            #endif
        }
    }

    private func executeToggleFollow() {
        Task {
            await followState.toggleFollow(ndk: ndk)
            onFollowChanged?(followState.isFollowing)

            // Success haptic
            #if canImport(UIKit)
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
            #endif
        }
    }

    private func setupFollowObservation() {
        Task {
            await followState.startObserving(ndk: ndk)
        }
    }

    // MARK: - Style Properties

    private var buttonSpacing: CGFloat {
        switch style {
        case .standard: return 6
        case .compact: return 4
        case .minimal: return 4
        }
    }

    private var iconFont: Font {
        switch style {
        case .standard: return .body
        case .compact: return .callout
        case .minimal: return .body
        }
    }

    private var textFont: Font {
        switch style {
        case .standard: return .body
        case .compact: return .caption
        case .minimal: return .body
        }
    }

    private var buttonPadding: EdgeInsets {
        switch style {
        case .standard: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        case .compact: return EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        case .minimal: return EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard:
            return followState.isFollowing ? Color.ndkSecondaryBackground : Color.accentColor
        case .compact:
            return followState.isFollowing ? Color.ndkSecondaryBackground : Color.accentColor.opacity(OpacityConstants.subtle)
        case .minimal:
            return Color.clear
        }
    }

    private var borderOverlay: some View {
        Group {
            if style == .standard || (style == .compact && followState.isFollowing) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        followState.isFollowing ? Color.ndkSeparator : Color.clear,
                        lineWidth: followState.isFollowing ? 1 : 0
                    )
            }
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .standard: return 20
        case .compact: return 16
        case .minimal: return 8
        }
    }

    private var iconColor: Color {
        if followState.isFollowing {
            return .secondary
        } else {
            return style == .standard ? .white : .accentColor
        }
    }

    private var textColor: Color {
        if followState.isFollowing {
            return .primary
        } else {
            return style == .standard ? .white : .accentColor
        }
    }

    // MARK: - Modifiers

    /// Handle follow state changes
    public func onFollowChanged(_ action: @escaping (Bool) -> Void) -> NDKUIFollowButton {
        var copy = self
        copy.onFollowChanged = action
        return copy
    }
}

// MARK: - FollowState

/// Observable state for managing follow relationships using session data
@MainActor
private class FollowState: ObservableObject {
    @Published var isFollowing: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?

    private let targetPubkey: String
    private var observationTask: Task<Void, Never>?

    init(targetPubkey: String) {
        self.targetPubkey = targetPubkey
    }

    deinit {
        observationTask?.cancel()
    }

    func startObserving(ndk: NDK) async {
        // Cancel existing observation
        observationTask?.cancel()

        // Initial state from session data
        updateFromSessionData(ndk: ndk)

        // Observe session data changes via withObservationTracking
        observationTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        // Access the observable property to track it
                        _ = ndk.sessionData?.contactList
                    } onChange: {
                        continuation.resume()
                    }
                }
                // Update state when contact list changes
                await MainActor.run {
                    self.updateFromSessionData(ndk: ndk)
                }
            }
        }
    }

    private func updateFromSessionData(ndk: NDK) {
        isFollowing = ndk.sessionData?.contactList?.isFollowing(targetPubkey) ?? false
    }

    func toggleFollow(ndk: NDK) async {
        if isFollowing {
            await unfollowUser(ndk: ndk)
        } else {
            await followUser(ndk: ndk)
        }
    }

    func followUser(ndk: NDK) async {
        guard ndk.signer != nil else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Get or create contact list from session data
            let contactList = ndk.sessionData?.contactList ?? NDKContactList(ndk: ndk)
            contactList.addContact(pubkey: targetPubkey)

            // Sign and publish
            try await contactList.sign()
            _ = try await ndk.publish(contactList.toNDKEvent())

        } catch {
            self.error = error
            NDKLogger.log(.error, category: .general, "Failed to follow user: \(error)")
        }
    }

    func unfollowUser(ndk: NDK) async {
        guard ndk.signer != nil else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Get contact list from session data
            guard let contactList = ndk.sessionData?.contactList else { return }
            contactList.removeContact(pubkey: targetPubkey)

            // Sign and publish
            try await contactList.sign()
            _ = try await ndk.publish(contactList.toNDKEvent())

        } catch {
            self.error = error
            NDKLogger.log(.error, category: .general, "Failed to unfollow user: \(error)")
        }
    }
}

// MARK: - Convenience Extensions

public extension NDKUIFollowButton {
    /// Create a compact follow button (icon only)
    static func compact(ndk: NDK, pubkey: String) -> NDKUIFollowButton {
        NDKUIFollowButton(ndk: ndk, pubkey: pubkey, style: .compact, showFollowText: false)
    }

    /// Create a minimal follow button (text only)
    static func minimal(ndk: NDK, pubkey: String) -> NDKUIFollowButton {
        NDKUIFollowButton(ndk: ndk, pubkey: pubkey, style: .minimal)
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIFollowButton_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK: NDK = { fatalError("NDK requires async cache init") }()

            VStack(spacing: 20) {
                // Different styles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Standard Styles")
                        .font(.headline)

                    HStack(spacing: 16) {
                        NDKUIFollowButton(ndk: mockNDK, pubkey: "mock_pubkey", style: .standard)
                        NDKUIFollowButton(ndk: mockNDK, pubkey: "mock_pubkey", style: .compact)
                        NDKUIFollowButton(ndk: mockNDK, pubkey: "mock_pubkey", style: .minimal)
                    }
                }

                // Compact variations
                VStack(alignment: .leading, spacing: 12) {
                    Text("Compact Variations")
                        .font(.headline)

                    HStack(spacing: 16) {
                        NDKUIFollowButton.compact(ndk: mockNDK, pubkey: "mock_pubkey")
                        NDKUIFollowButton(ndk: mockNDK, pubkey: "mock_pubkey", style: .compact, showFollowText: true)
                    }
                }

                // Different states (would need state management for proper preview)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Different States")
                        .font(.headline)

                    HStack(spacing: 16) {
                        NDKUIFollowButton(ndk: mockNDK, pubkey: "mock_pubkey") // Not following
                        // NDKUIFollowButton(ndk: mockNDK, pubkey: "mock_pubkey") // Following (would need state)
                    }
                }
            }
            .padding()
        }
    }
#endif
