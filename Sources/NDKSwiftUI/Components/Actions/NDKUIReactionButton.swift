import NDKSwiftCore
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - NDKUIReactionButton

/// A button component for reacting to Nostr events with customizable emoji reactions.
///
/// Features:
/// - Toggle reaction states (liked/unliked)
/// - Real-time reaction counts
/// - Custom emoji support
/// - Haptic feedback
/// - Animation states
/// - Batch reaction loading
///
/// ## Usage
///
/// ```swift
/// // Basic like button
/// NDKUIReactionButton(ndk: ndk, event: event, reaction: "❤️")
///     .onReactionChanged { isReacted in
///         print("User \(isReacted ? "liked" : "unliked") the post")
///     }
///
/// // Custom emoji with styling
/// NDKUIReactionButton(ndk: ndk, event: event, reaction: "🤙", style: .compact, showCount: true)
/// ```
public struct NDKUIReactionButton: View {
    // MARK: - Properties

    private let ndk: NDK
    private let event: NDKEvent
    private let reaction: String
    private let style: ButtonStyle
    private let showCount: Bool
    private let animateChanges: Bool
    private var onReactionChanged: ((Bool) -> Void)?

    @StateObject private var reactionState: ReactionState

    // MARK: - Supporting Types

    public enum ButtonStyle {
        case standard // Medium size with background
        case compact // Small size, icon only
        case minimal // Text-based, no background
    }

    // MARK: - Initialization

    /// Initialize a reaction button
    /// - Parameters:
    ///   - ndk: The NDK instance to use for operations
    ///   - event: The event to react to
    ///   - reaction: The emoji reaction (default: "❤️")
    ///   - style: Button presentation style
    ///   - showCount: Whether to show reaction count
    ///   - animateChanges: Whether to animate state changes
    public init(
        ndk: NDK,
        event: NDKEvent,
        reaction: String = "❤️",
        style: ButtonStyle = .standard,
        showCount: Bool = true,
        animateChanges: Bool = true
    ) {
        self.ndk = ndk
        self.event = event
        self.reaction = reaction
        self.style = style
        self.showCount = showCount
        self.animateChanges = animateChanges

        // Initialize reaction state
        _reactionState = StateObject(wrappedValue: ReactionState(
            eventId: event.id,
            reaction: reaction
        ))
    }

    // MARK: - Body

    public var body: some View {
        Button(action: toggleReaction) {
            HStack(spacing: buttonSpacing) {
                // Reaction emoji
                Text(reaction)
                    .font(reactionFont)
                    .scaleEffect(reactionState.isReacted && animateChanges ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: reactionState.isReacted)

                // Count (if enabled and > 0)
                if showCount && reactionState.count > 0 {
                    Text("\(reactionState.count)")
                        .font(countFont)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: reactionState.count)
                }
            }
            .foregroundStyle(reactionState.isReacted ? activeColor : inactiveColor)
            .padding(buttonPadding)
            .background(backgroundColor)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(reactionState.isLoading)
        .opacity(reactionState.isLoading ? OpacityConstants.overlay : 1.0)
        .onAppear {
            setupReactionObservation()
        }
    }

    // MARK: - Private Methods

    private func toggleReaction() {
        Task {
            await reactionState.toggleReaction(ndk: ndk, event: event)
            onReactionChanged?(reactionState.isReacted)
        }

        // Haptic feedback
        #if canImport(UIKit)
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        #endif
    }

    private func setupReactionObservation() {
        Task {
            await reactionState.startObserving(ndk: ndk)
        }
    }

    // MARK: - Style Properties

    private var buttonSpacing: CGFloat {
        switch style {
        case .standard: return 4
        case .compact: return 2
        case .minimal: return 4
        }
    }

    private var reactionFont: Font {
        switch style {
        case .standard: return .title3
        case .compact: return .body
        case .minimal: return .body
        }
    }

    private var countFont: Font {
        switch style {
        case .standard: return .caption
        case .compact: return .caption2
        case .minimal: return .caption
        }
    }

    private var buttonPadding: EdgeInsets {
        switch style {
        case .standard: return EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        case .compact: return EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        case .minimal: return EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard:
            return reactionState.isReacted ? activeColor.opacity(OpacityConstants.subtle) : Color.ndkTertiaryBackground
        case .compact:
            return reactionState.isReacted ? activeColor.opacity(OpacityConstants.subtle) : Color.clear
        case .minimal:
            return Color.clear
        }
    }

    private var borderOverlay: some View {
        Group {
            if style == .standard {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(reactionState.isReacted ? activeColor.opacity(OpacityConstants.border) : Color.ndkSeparator.opacity(OpacityConstants.border), lineWidth: 1)
            }
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .standard: return 16
        case .compact: return 12
        case .minimal: return 8
        }
    }

    private var activeColor: Color {
        // Different colors for different reactions
        switch reaction {
        case "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎": return .red
        case "👍", "🤙", "💪", "🙌", "👏", "🔥": return .orange
        case "😂", "🤣", "😆", "😁", "😄": return .yellow
        case "⚡", "🌟": return .yellow
        default: return .accentColor
        }
    }

    private var inactiveColor: Color {
        .secondary
    }

    // MARK: - Modifiers

    /// Handle reaction state changes
    public func onReactionChanged(_ action: @escaping (Bool) -> Void) -> NDKUIReactionButton {
        var copy = self
        copy.onReactionChanged = action
        return copy
    }
}

// MARK: - ReactionState

/// Observable state for managing reaction data and interactions
@MainActor
private class ReactionState: ObservableObject {
    @Published var isReacted: Bool = false
    @Published var count: Int = 0
    @Published var isLoading: Bool = false

    private let eventId: String
    private let reaction: String
    private var reactionEventId: String?
    private var observationTask: Task<Void, Never>?

    init(eventId: String, reaction: String) {
        self.eventId = eventId
        self.reaction = reaction
    }

    deinit {
        observationTask?.cancel()
    }

    func startObserving(ndk: NDK) async {
        // Cancel existing observation
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            await self?.observeReactions(ndk: ndk)
        }
    }

    private func observeReactions(ndk: NDK) async {
        // Create filter for reaction events (kind:7) referencing our event
        let filter = NDKFilter(
            kinds: [EventKind.reaction], // Reaction events
            tags: ["e": Set([eventId])] // Events that reference our event
        )

        let dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0, // Real-time
            cachePolicy: .cacheWithNetwork
        )

        // Accumulate reactions locally
        var allReactions: [String: NDKEvent] = [:] // id -> event
        let userPubkey = try? await ndk.signer?.pubkey

        // Process reaction events as they stream in
        for await batch in dataSource.events {
            for event in batch {
                allReactions[event.id] = event
            }
            updateReactionState(from: Array(allReactions.values), userPubkey: userPubkey)
        }
    }

    private func updateReactionState(from events: [NDKEvent], userPubkey: String?) {
        var totalCount = 0
        var userReacted = false
        var userReactionEventId: String?

        // Process all reaction events matching our emoji
        for event in events where event.content == reaction {
            totalCount += 1

            // Check if this is the current user's reaction
            if let userPubkey = userPubkey, event.pubkey == userPubkey {
                userReacted = true
                userReactionEventId = event.id
            }
        }

        // Update state
        count = totalCount
        isReacted = userReacted
        reactionEventId = userReactionEventId
    }

    func toggleReaction(ndk: NDK, event: NDKEvent) async {
        guard let signer = ndk.signer else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            if isReacted {
                // Remove reaction (delete the reaction event)
                if let reactionEventId = reactionEventId {
                    let deleteEvent = try await NDKEventBuilder(ndk: ndk)
                        .kind(EventKind.deletion) // Deletion event
                        .content("Removing reaction")
                        .tag(["e", reactionEventId])
                        .build(signer: signer)

                    _ = try await ndk.publish(deleteEvent)
                }
            } else {
                // Add reaction
                let reactionEvent = try await NDKEventBuilder(ndk: ndk)
                    .kind(EventKind.reaction) // Reaction event
                    .content(reaction)
                    .tag(["e", event.id])
                    .tag(["p", event.pubkey])
                    .build(signer: signer)

                _ = try await ndk.publish(reactionEvent)
            }
        } catch {
            NDKLogger.log(.error, category: .general, "Failed to toggle reaction: \(error)")
        }
    }
}

// MARK: - Convenience Extensions

public extension NDKUIReactionButton {
    /// Create a like button (❤️)
    static func like(ndk: NDK, event: NDKEvent, style: ButtonStyle = .standard) -> NDKUIReactionButton {
        NDKUIReactionButton(ndk: ndk, event: event, reaction: "❤️", style: style)
    }

    /// Create a repost button (🔄)
    static func repost(ndk: NDK, event: NDKEvent, style: ButtonStyle = .standard) -> NDKUIReactionButton {
        NDKUIReactionButton(ndk: ndk, event: event, reaction: "🔄", style: style)
    }

    /// Create a fire button (🔥)
    static func fire(ndk: NDK, event: NDKEvent, style: ButtonStyle = .standard) -> NDKUIReactionButton {
        NDKUIReactionButton(ndk: ndk, event: event, reaction: "🔥", style: style)
    }

    /// Create a thumbs up button (👍)
    static func thumbsUp(ndk: NDK, event: NDKEvent, style: ButtonStyle = .standard) -> NDKUIReactionButton {
        NDKUIReactionButton(ndk: ndk, event: event, reaction: "👍", style: style)
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIReactionButton_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK = NDK(relayURLs: [])

            VStack(spacing: 20) {
                // Different styles
                HStack(spacing: 16) {
                    NDKUIReactionButton.like(ndk: mockNDK, event: mockEvent, style: .standard)
                    NDKUIReactionButton.like(ndk: mockNDK, event: mockEvent, style: .compact)
                    NDKUIReactionButton.like(ndk: mockNDK, event: mockEvent, style: .minimal)
                }

                // Different reactions
                HStack(spacing: 16) {
                    NDKUIReactionButton.like(ndk: mockNDK, event: mockEvent)
                    NDKUIReactionButton.fire(ndk: mockNDK, event: mockEvent)
                    NDKUIReactionButton.thumbsUp(ndk: mockNDK, event: mockEvent)
                    NDKUIReactionButton(ndk: mockNDK, event: mockEvent, reaction: "🤙")
                }
            }
            .padding()
        }

        // Mock event for preview
        private static let mockEvent = NDKEvent(
            id: "mock_id",
            pubkey: "mock_pubkey",
            createdAt: Date.currentNostrTimestamp,
            kind: EventKind.textNote,
            tags: [],
            content: "Mock event content",
            sig: "mock_sig"
        )
    }
#endif
