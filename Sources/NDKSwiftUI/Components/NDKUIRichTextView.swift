import SwiftUI
import NDKSwift

/// A comprehensive rich text view that renders parsed Nostr content with reactive profile loading and interactive elements
public struct NDKUIRichTextView: View {
    private let ndk: NDK
    let content: String
    let tags: [Tag]
    let currentUser: NDKUser?
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
        case full           // Full rendering with previews
        case compact        // Inline rendering without previews
        case minimal        // Basic text only
    }
    
    public init(
        ndk: NDK,
        content: String,
        tags: [Tag] = [],
        currentUser: NDKUser? = nil,
        showLinkPreviews: Bool = true,
        style: Style = .full
    ) {
        self.ndk = ndk
        self.content = content
        self.tags = tags
        self.currentUser = currentUser
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
                            NDKUIURLPreview(ndk: ndk, url: url, style: previewStyle)
                                .padding(.top, 4)
                        }
                        
                        // Show event previews
                        ForEach(extractEventReferences(from: parsed.components), id: \.self) { reference in
                            NDKUIEventPreview(eventReference: reference)
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
            case .text(let text):
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
        case .text(let text):
            return Text(text)
            
        case .userMention(let pubkey, let npub):
            let displayName = profileCache[pubkey]?.displayName ?? profileCache[pubkey]?.name
            let text = displayName != nil ? "@\(displayName!)" : "@\(String(npub.prefix(16)))..."
            return Text(text)
                .foregroundColor(.ndkAccent)
                .fontWeight(mentionFontWeight)
            
        case .npubMention(let npub):
            // Try to get pubkey and load profile
            if let pubkey = try? String.fromNpub(npub) {
                let displayName = profileCache[pubkey]?.displayName ?? profileCache[pubkey]?.name
                let text = displayName != nil ? "@\(displayName!)" : "@\(String(npub.prefix(16)))..."
                return Text(text)
                    .foregroundColor(.ndkAccent)
                    .fontWeight(mentionFontWeight)
            } else {
                return Text("@\(String(npub.prefix(16)))...")
                    .foregroundColor(.ndkAccent)
                    .fontWeight(mentionFontWeight)
            }
            
        case .nprofileMention(let nprofile):
            // For now, just show truncated nprofile
            return Text("@\(String(nprofile.prefix(16)))...")
                .foregroundColor(.ndkAccent)
                .fontWeight(mentionFontWeight)
            
        case .eventMention(let eventId):
            return Text("📝 \(String(eventId.prefix(8)))...")
                .foregroundColor(.ndkAccent)
                .underline()
            
        case .noteMention(let note):
            return Text("📝 \(String(note.prefix(16)))...")
                .foregroundColor(.ndkAccent)
                .underline()
            
        case .neventMention(let nevent):
            return Text("📝 \(String(nevent.prefix(16)))...")
                .foregroundColor(.ndkAccent)
                .underline()
            
        case .hashtag(let tag):
            return Text("#\(tag)")
                .foregroundColor(.ndkAccent)
                .fontWeight(hashtagFontWeight)
            
        case .url(let url):
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
        let parsed = await ndk.parseContent(content, tags: tags, currentUser: currentUser)
        
        await MainActor.run {
            self.parsedContent = parsed
        }
    }
    
    private func loadProfilesForComponents(_ components: [NDKParsedContent.Component]) {
        for component in components {
            switch component {
            case .userMention(let pubkey, _):
                loadProfile(for: pubkey)
            case .npubMention(let npub):
                if let pubkey = try? String.fromNpub(npub) {
                    loadProfile(for: pubkey)
                }
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
            if case .url(let url) = component {
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
            case .eventMention(let eventId):
                references.append(.eventId(eventId))
            case .noteMention(let note):
                references.append(.note(note))
            case .neventMention(let nevent):
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

/// A view for previewing event references (stub for now)
public struct NDKUIEventPreview: View {
    let eventReference: EventReference
    
    public enum EventReference: Hashable {
        case eventId(String)
        case note(String)
        case nevent(String)
    }
    
    public var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.ndkAccent)
            
            Text("Event preview")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
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
    let currentUser: NDKUser?
    
    public init(ndk: NDK, content: String, tags: [Tag] = [], currentUser: NDKUser? = nil) {
        self.ndk = ndk
        self.content = content
        self.tags = tags
        self.currentUser = currentUser
    }
    
    public var body: some View {
        NDKUIRichTextView(
            ndk: ndk,
            content: content,
            tags: tags,
            currentUser: currentUser,
            showLinkPreviews: false,
            style: .minimal
        )
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIRichTextView_Previews: PreviewProvider {
    static var previews: some View {
        let mockNDK = NDK(relayUrls: [])
        
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