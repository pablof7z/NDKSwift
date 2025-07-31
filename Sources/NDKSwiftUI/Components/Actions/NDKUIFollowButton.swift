import SwiftUI
import NDKSwift

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
/// NDKUIFollowButton(pubkey: user.pubkey)
///     .onFollowChanged { isFollowing in
///         print("User is \(isFollowing ? "followed" : "unfollowed")")
///     }
///
/// // Custom styling
/// NDKUIFollowButton(pubkey: user.pubkey)
///     .style(.compact)
///     .showFollowText(false)
/// ```
public struct NDKUIFollowButton: View {

    // MARK: - Properties

    private let pubkey: String
    private let style: ButtonStyle
    private let showFollowText: Bool
    private let confirmUnfollow: Bool
    private var onFollowChanged: ((Bool) -> Void)?

    @Environment(\.ndk) private var ndk
    @StateObject private var followState: FollowState
    @State private var showUnfollowConfirmation = false

    // MARK: - Supporting Types

    public enum ButtonStyle {
        case standard       // Full button with text
        case compact        // Icon-based button
        case minimal        // Text-only button
    }

    // MARK: - Initialization

    /// Initialize a follow button
    /// - Parameters:
    ///   - pubkey: The public key of the user to follow/unfollow
    ///   - style: Button presentation style
    ///   - showFollowText: Whether to show "Follow"/"Following" text
    ///   - confirmUnfollow: Whether to show confirmation before unfollowing
    public init(
        pubkey: String,
        style: ButtonStyle = .standard,
        showFollowText: Bool = true,
        confirmUnfollow: Bool = true
    ) {
        self.pubkey = pubkey
        self.style = style
        self.showFollowText = showFollowText
        self.confirmUnfollow = confirmUnfollow

        // Initialize follow state
        self._followState = StateObject(wrappedValue: FollowState(targetPubkey: pubkey))
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
        .disabled(followState.isLoading || ndk?.signer == nil)
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
            guard let ndk = ndk else { return }
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
            guard let ndk = ndk else { return }
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
        guard let ndk = ndk else { return }

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

/// Observable state for managing follow relationships and contact list updates
@MainActor
private class FollowState: ObservableObject {

    @Published var isFollowing: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?

    private let targetPubkey: String
    private var currentContactList: [String] = []
    private var currentContactListEvent: NDKEvent?
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

        guard let signer = ndk.signer,
              let userPubkey = try? await signer.pubkey else { return }

        observationTask = Task { [weak self] in
            await self?.observeContactList(ndk: ndk, userPubkey: userPubkey)
        }
    }

    private func observeContactList(ndk: NDK, userPubkey: String) async {
        // Create filter for user's contact list (kind:3)
        let filter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.contacts]
        )

        let dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0, // Real-time
            cachePolicy: .cacheWithNetwork
        )

        // Process contact list events
        for await events in dataSource.$data.values {
            await updateFollowState(from: events)
        }
    }

    private func updateFollowState(from events: [NDKEvent]) async {
        // Get the most recent contact list event
        let sortedEvents = events.sorted { $0.createdAt > $1.createdAt }
        guard let latestEvent = sortedEvents.first else { return }

        // Parse contact list
        var contacts: [String] = []
        for tag in latestEvent.tags {
            if tag.count >= 2 && tag[0] == "p" {
                contacts.append(tag[1])
            }
        }

        // Update state
        self.currentContactList = contacts
        self.currentContactListEvent = latestEvent
        self.isFollowing = contacts.contains(self.targetPubkey)
    }

    func toggleFollow(ndk: NDK) async {
        if isFollowing {
            await unfollowUser(ndk: ndk)
        } else {
            await followUser(ndk: ndk)
        }
    }

    func followUser(ndk: NDK) async {
        guard let signer = ndk.signer else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Add to contact list
            var newContactList = currentContactList
            if !newContactList.contains(targetPubkey) {
                newContactList.append(targetPubkey)
            }

            // Create new contact list event
            let contactListEvent = try await buildContactListEvent(
                ndk: ndk,
                signer: signer,
                contacts: newContactList
            )

            // Publish the updated contact list
            _ = try await ndk.publish(contactListEvent)

        } catch {
            self.error = error
            NDKLogger.log(.error, category: .general, "Failed to follow user: \(error)")
        }
    }

    func unfollowUser(ndk: NDK) async {
        guard let signer = ndk.signer else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Remove from contact list
            let newContactList = currentContactList.filter { $0 != targetPubkey }

            // Create new contact list event
            let contactListEvent = try await buildContactListEvent(
                ndk: ndk,
                signer: signer,
                contacts: newContactList
            )

            // Publish the updated contact list
            _ = try await ndk.publish(contactListEvent)

        } catch {
            self.error = error
            NDKLogger.log(.error, category: .general, "Failed to unfollow user: \(error)")
        }
    }

    private func buildContactListEvent(
        ndk: NDK,
        signer: NDKSigner,
        contacts: [String]
    ) async throws -> NDKEvent {

        let eventBuilder = NDKEventBuilder(ndk: ndk)
            .kind(EventKind.contacts) // Contact list
            .content(currentContactListEvent?.content ?? "") // Preserve existing content

        // Add contact tags
        for contact in contacts {
            eventBuilder.tag(["p", contact])
        }

        // Preserve other non-p tags from the current contact list
        if let currentEvent = currentContactListEvent {
            for tag in currentEvent.tags {
                if tag.count >= 1 && tag[0] != "p" {
                    eventBuilder.tag(tag)
                }
            }
        }

        return try await eventBuilder.build(signer: signer)
    }
}

// MARK: - Convenience Extensions

public extension NDKUIFollowButton {

    /// Create a compact follow button (icon only)
    static func compact(pubkey: String) -> NDKUIFollowButton {
        NDKUIFollowButton(pubkey: pubkey, style: .compact, showFollowText: false)
    }

    /// Create a minimal follow button (text only)
    static func minimal(pubkey: String) -> NDKUIFollowButton {
        NDKUIFollowButton(pubkey: pubkey, style: .minimal)
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIFollowButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Different styles
            VStack(alignment: .leading, spacing: 12) {
                Text("Standard Styles")
                    .font(.headline)

                HStack(spacing: 16) {
                    NDKUIFollowButton(pubkey: "mock_pubkey", style: .standard)
                    NDKUIFollowButton(pubkey: "mock_pubkey", style: .compact)
                    NDKUIFollowButton(pubkey: "mock_pubkey", style: .minimal)
                }
            }

            // Compact variations
            VStack(alignment: .leading, spacing: 12) {
                Text("Compact Variations")
                    .font(.headline)

                HStack(spacing: 16) {
                    NDKUIFollowButton.compact(pubkey: "mock_pubkey")
                    NDKUIFollowButton(pubkey: "mock_pubkey", style: .compact, showFollowText: true)
                }
            }

            // Different states (would need state management for proper preview)
            VStack(alignment: .leading, spacing: 12) {
                Text("Different States")
                    .font(.headline)

                HStack(spacing: 16) {
                    NDKUIFollowButton(pubkey: "mock_pubkey") // Not following
                    // NDKUIFollowButton(pubkey: "mock_pubkey") // Following (would need state)
                }
            }
        }
        .padding()
        .environment(\.ndk, nil) // Mock environment
    }
}
#endif
