import NDKSwiftCore
import SwiftUI

/// A comprehensive rich text view that renders parsed Nostr content with reactive profile loading and interactive elements
public struct NDKUIRichTextView: View {
    private let ndk: NDK
    let content: String
    let tags: [Tag]
    let currentUserPubkey: PublicKey?
    let showLinkPreviews: Bool
    let style: Style
    @State private var parsedContent: NDKParsedContent?
    @State private var profileCache: [String: NDKUserMetadata] = [:]
    @State private var profileTasks: [String: Task<Void, Never>] = [:]
    @State private var trackedPubkeys: Set<String> = []

    // Callbacks
    private var onLinkTapped: ((URL) -> Void)?
    private var onHashtagTapped: ((String) -> Void)?
    private var onMentionTapped: ((String) -> Void)?
    private var onEventTapped: ((String) -> Void)?

    public enum Style {
        case full // Full rendering with previews
        case compact // Inline rendering without previews
        case minimal // Basic text only
    }

    public init(
        ndk: NDK,
        content: String,
        tags: [Tag] = [],
        currentUserPubkey: PublicKey? = nil,
        showLinkPreviews: Bool = true,
        style: Style = .full
    ) {
        self.ndk = ndk
        self.content = content
        self.tags = tags
        self.currentUserPubkey = currentUserPubkey
        self.showLinkPreviews = showLinkPreviews && style == .full
        self.style = style
    }

    public var body: some View {
        Group {
            if let parsed = parsedContent {
                VStack(alignment: .leading, spacing: 8) {
                    renderComponents(parsed.components)
                        .onAppear {
                            loadProfilesForComponents(parsed.components)
                        }

                    // Show URL previews below the text
                    if showLinkPreviews {
                        ForEach(extractURLs(from: parsed.components), id: \.absoluteString) { url in
                            NDKUIURLPreview(url: url, style: previewStyle)
                                .padding(.top, 4)
                        }

                        // Show event previews
                        ForEach(extractEventReferences(from: parsed.components), id: \.self) { reference in
                            NDKUIEventPreview(ndk: ndk, eventReference: reference)
                                .padding(.top, 4)
                        }
                    }
                }
            } else {
                Text(content)
                    .task {
                        await parseContent()
                    }
            }
        }
        .onDisappear {
            // Cancel all profile loading tasks
            for task in profileTasks.values {
                task.cancel()
            }
        }
    }

    // MARK: - Modifiers

    public func onLinkTapped(_ action: @escaping (URL) -> Void) -> Self {
        var copy = self
        copy.onLinkTapped = action
        return copy
    }

    public func onHashtagTapped(_ action: @escaping (String) -> Void) -> Self {
        var copy = self
        copy.onHashtagTapped = action
        return copy
    }

    public func onMentionTapped(_ action: @escaping (String) -> Void) -> Self {
        var copy = self
        copy.onMentionTapped = action
        return copy
    }

    public func onEventTapped(_ action: @escaping (String) -> Void) -> Self {
        var copy = self
        copy.onEventTapped = action
        return copy
    }

    // MARK: - Private Methods

    @ViewBuilder
    private func renderComponents(_ components: [NDKParsedContent.Component]) -> some View {
        // Combine adjacent text components for better text flow
        let mergedComponents = mergeTextComponents(components)

        // Create text with attributed components
        mergedComponents.reduce(Text("")) { result, component in
            result + renderComponent(component)
        }
    }

    private func mergeTextComponents(_ components: [NDKParsedContent.Component]) -> [NDKParsedContent.Component] {
        var merged: [NDKParsedContent.Component] = []
        var currentText = ""

        for component in components {
            switch component {
            case let .text(text):
                currentText += text
            default:
                if !currentText.isEmpty {
                    merged.append(.text(currentText))
                    currentText = ""
                }
                merged.append(component)
            }
        }

        if !currentText.isEmpty {
            merged.append(.text(currentText))
        }

        return merged
    }

    private func renderComponent(_ component: NDKParsedContent.Component) -> Text {
        switch component {
        case let .text(text):
            return Text(text)

        case let .userMention(pubkey, npub):
            let displayName = profileCache[pubkey]?.displayName ?? profileCache[pubkey]?.name
            let text = displayName != nil ? "@\(displayName!)" : "@\(String(npub.prefix(16)))..."
            return Text(text)
                .foregroundColor(.ndkAccent)
                .fontWeight(mentionFontWeight)

        case let .nprofileMention(nprofile):
            // For now, just show truncated nprofile
            return Text("@\(String(nprofile.prefix(16)))...")
                .foregroundColor(.ndkAccent)
                .fontWeight(mentionFontWeight)

        case let .eventMention(eventId):
            return Text("📝 \(String(eventId.prefix(8)))...")
                .foregroundColor(.ndkAccent)
                .underline()

        case let .noteMention(note):
            return Text("📝 \(String(note.prefix(16)))...")
                .foregroundColor(.ndkAccent)
                .underline()

        case let .neventMention(nevent):
            return Text("📝 \(String(nevent.prefix(16)))...")
                .foregroundColor(.ndkAccent)
                .underline()

        case let .hashtag(tag):
            return Text("#\(tag)")
                .foregroundColor(.ndkAccent)
                .fontWeight(hashtagFontWeight)

        case let .url(url):
            // Don't render image URLs as text if we're showing previews
            if showLinkPreviews && isImageURL(url) {
                return Text("")
            } else {
                return Text(url.absoluteString)
                    .foregroundColor(.ndkAccent)
                    .underline()
            }
        }
    }

    private func parseContent() async {
        let parsed = await ndk.parseContent(content, tags: tags, currentUserPubkey: currentUserPubkey)

        await MainActor.run {
            self.parsedContent = parsed
        }
    }

    private func loadProfilesForComponents(_ components: [NDKParsedContent.Component]) {
        for component in components {
            switch component {
            case let .userMention(pubkey, _):
                loadProfile(for: pubkey)
            default:
                break
            }
        }
    }

    private func loadProfile(for pubkey: String) {
        // Skip if already loading or loaded
        guard !trackedPubkeys.contains(pubkey) else { return }

        trackedPubkeys.insert(pubkey)

        let task = Task {
            let profileStream = await ndk.profileManager.subscribe(for: pubkey, maxAge: TimeConstants.hour)

            for await profile in profileStream {
                if let profile = profile {
                    await MainActor.run {
                        self.profileCache[pubkey] = profile
                    }
                    break // We only need the first profile
                }
            }
        }

        profileTasks[pubkey] = task
    }

    private func extractURLs(from components: [NDKParsedContent.Component]) -> [URL] {
        var urls: [URL] = []

        for component in components {
            if case let .url(url) = component {
                urls.append(url)
            }
        }

        // Limit to first 3 URLs to avoid overwhelming the UI
        return Array(urls.prefix(3))
    }

    private func extractEventReferences(from components: [NDKParsedContent.Component]) -> [NDKUIEventPreview.EventReference] {
        var references: [NDKUIEventPreview.EventReference] = []

        for component in components {
            switch component {
            case let .eventMention(eventId):
                references.append(.eventId(eventId))
            case let .noteMention(note):
                references.append(.note(note))
            case let .neventMention(nevent):
                references.append(.nevent(nevent))
            default:
                break
            }
        }

        // Limit to first 2 event references
        return Array(references.prefix(2))
    }

    private func isImageURL(_ url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff"]
        let pathExtension = url.pathExtension.lowercased()

        if imageExtensions.contains(pathExtension) {
            return true
        }

        // Also check if URL contains image extension before query params
        let urlString = url.absoluteString.lowercased()
        for ext in imageExtensions {
            if urlString.contains(".\(ext)?") || urlString.contains(".\(ext)&") || urlString.contains(".\(ext)#") {
                return true
            }
        }

        return false
    }

    // MARK: - Style Properties

    private var previewStyle: NDKUIURLPreview.Style {
        switch style {
        case .full: return .full
        case .compact: return .compact
        case .minimal: return .minimal
        }
    }

    private var mentionFontWeight: Font.Weight {
        switch style {
        case .full, .compact: return .semibold
        case .minimal: return .regular
        }
    }

    private var hashtagFontWeight: Font.Weight {
        switch style {
        case .full, .compact: return .medium
        case .minimal: return .regular
        }
    }
}

// MARK: - NDKUIEventPreview

/// A view for previewing event references
///
/// Follows NDKSwift's event-streaming philosophy: shows placeholder immediately,
/// updates progressively as event arrives. Never blocks with loading spinners.
public struct NDKUIEventPreview: View {
    let ndk: NDK
    let eventReference: EventReference

    @State private var event: NDKEvent?

    public enum EventReference: Hashable {
        case eventId(String)
        case note(String)
        case nevent(String)
    }

    public init(ndk: NDK, eventReference: EventReference) {
        self.ndk = ndk
        self.eventReference = eventReference
    }

    public var body: some View {
        Group {
            if let event = event {
                NDKUIEventView(ndk: ndk, event: event, style: .embedded, showInteractions: false)
            } else {
                // Show placeholder immediately - never a loading spinner
                EventPlaceholder()
            }
        }
        .task {
            await streamEvent()
        }
    }

    private func streamEvent() async {
        guard let eventId = extractEventId() else { return }

        let filter = NDKFilter(ids: [eventId])
        let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

        // Stream events progressively - update UI as they arrive
        for await event in subscription.events {
            await MainActor.run {
                self.event = event
            }
            break // First event is enough for preview
        }
    }

    private func extractEventId() -> String? {
        switch eventReference {
        case .eventId(let id):
            return id
        case .note(let note):
            return try? Bech32.eventId(from: note)
        case .nevent(let nevent):
            if let decoded = try? ContentTagger.decodeNostrEntity(nevent) {
                return decoded.eventId
            }
            return nil
        }
    }

    @ViewBuilder
    private func EventPlaceholder() -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 10)
                    .frame(width: 120)
            }
        }
        .padding()
        .background(Color.ndkSecondaryBackground)
        .cornerRadius(8)
    }
}

// MARK: - Inline Version

/// A simpler text-only version for use in list views
public struct NDKUIRichTextInline: View {
    private let ndk: NDK
    let content: String
    let tags: [Tag]
    let currentUserPubkey: PublicKey?

    public init(ndk: NDK, content: String, tags: [Tag] = [], currentUserPubkey: PublicKey? = nil) {
        self.ndk = ndk
        self.content = content
        self.tags = tags
        self.currentUserPubkey = currentUserPubkey
    }

    public var body: some View {
        NDKUIRichTextView(
            ndk: ndk,
            content: content,
            tags: tags,
            currentUserPubkey: currentUserPubkey,
            showLinkPreviews: false,
            style: .minimal
        )
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIRichTextView_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK = NDK(relayURLs: [])

            VStack(spacing: 20) {
                NDKUIRichTextView(
                    ndk: mockNDK,
                    content: "Hello @npub1234... check out #bitcoin at https://example.com",
                    style: .full
                )

                NDKUIRichTextView(
                    ndk: mockNDK,
                    content: "Simple inline text with #nostr",
                    style: .minimal
                )
            }
            .padding()
        }
    }
#endif
