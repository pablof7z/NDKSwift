import SwiftUI
import NDKSwift

/// A view that renders parsed Nostr content with reactive profile loading and URL previews
struct RichTextView: View {
    let content: String
    let tags: [Tag]
    let currentUser: NDKUser?
    let showLinkPreviews: Bool
    
    @Environment(NDKManager.self) var ndkManager
    @State private var parsedContent: NDKParsedContent?
    @State private var profileCache: [String: NDKUserProfile] = [:]
    @State private var profileTasks: [String: Task<Void, Never>] = [:]
    @State private var trackedPubkeys: Set<String> = []
    
    init(content: String, tags: [Tag], currentUser: NDKUser? = nil, showLinkPreviews: Bool = true) {
        self.content = content
        self.tags = tags
        self.currentUser = currentUser
        self.showLinkPreviews = showLinkPreviews
    }
    
    var body: some View {
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
                            URLPreviewView(url: url)
                                .padding(.top, 4)
                        }
                        
                        // Show event previews
                        ForEach(extractEventReferences(from: parsed.components), id: \.self) { reference in
                            EventPreviewView(eventReference: reference)
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
                .foregroundColor(.accentColor)
            
        case .npubMention(let npub):
            // Try to get pubkey and load profile
            if let pubkey = try? String.fromNpub(npub) {
                let displayName = profileCache[pubkey]?.displayName ?? profileCache[pubkey]?.name
                let text = displayName != nil ? "@\(displayName!)" : "@\(String(npub.prefix(16)))..."
                return Text(text)
                    .foregroundColor(.accentColor)
            } else {
                return Text("@\(String(npub.prefix(16)))...")
                    .foregroundColor(.accentColor)
            }
            
        case .nprofileMention(let nprofile):
            // For now, just show truncated nprofile
            // TODO: Decode nprofile to get pubkey when NDK supports it
            return Text("@\(String(nprofile.prefix(16)))...")
                .foregroundColor(.accentColor)
            
        case .eventMention(let eventId):
            return Text("📝 \(String(eventId.prefix(8)))...")
                .foregroundColor(.accentColor)
                .underline()
            
        case .noteMention(let note):
            return Text("📝 \(String(note.prefix(16)))...")
                .foregroundColor(.accentColor)
                .underline()
            
        case .neventMention(let nevent):
            return Text("📝 \(String(nevent.prefix(16)))...")
                .foregroundColor(.accentColor)
                .underline()
            
        case .hashtag(let tag):
            return Text("#\(tag)")
                .foregroundColor(.accentColor)
            
        case .url(let url):
            // Don't render image URLs as text - they'll be shown as images below
            if isImageURL(url) {
                return Text("")
            } else {
                return Text(url.absoluteString)
                    .foregroundColor(.accentColor)
                    .underline()
            }
        }
    }
    
    private func parseContent() async {
        guard let ndk = ndkManager.ndk else { return }
        
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
        guard !trackedPubkeys.contains(pubkey),
              let ndk = ndkManager.ndk else { return }
        
        trackedPubkeys.insert(pubkey)
        
        let task = Task {
            let profileStream = await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour)
            
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
    
    private func extractEventReferences(from components: [NDKParsedContent.Component]) -> [EventPreviewView.EventReference] {
        var references: [EventPreviewView.EventReference] = []
        
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
}

/// A simpler text-only version for use in list views
struct RichTextInline: View {
    let content: String
    let tags: [Tag]
    let currentUser: NDKUser?
    
    @Environment(NDKManager.self) var ndkManager
    @State private var parsedContent: NDKParsedContent?
    @State private var profileCache: [String: NDKUserProfile] = [:]
    @State private var profileTasks: [String: Task<Void, Never>] = [:]
    @State private var trackedPubkeys: Set<String> = []
    
    var body: some View {
        Group {
            if let parsed = parsedContent {
                renderComponents(parsed.components)
                    .onAppear {
                        loadProfilesForComponents(parsed.components)
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
                .foregroundColor(.accentColor)
            
        case .npubMention(let npub):
            // Try to get pubkey and load profile
            if let pubkey = try? String.fromNpub(npub) {
                let displayName = profileCache[pubkey]?.displayName ?? profileCache[pubkey]?.name
                let text = displayName != nil ? "@\(displayName!)" : "@\(String(npub.prefix(16)))..."
                return Text(text)
                    .foregroundColor(.accentColor)
            } else {
                return Text("@\(String(npub.prefix(16)))...")
                    .foregroundColor(.accentColor)
            }
            
        case .nprofileMention(let nprofile):
            // For now, just show truncated nprofile
            return Text("@\(String(nprofile.prefix(16)))...")
                .foregroundColor(.accentColor)
            
        case .eventMention(let eventId):
            return Text("📝 \(String(eventId.prefix(8)))...")
                .foregroundColor(.accentColor)
                .underline()
            
        case .noteMention(let note):
            return Text("📝 \(String(note.prefix(16)))...")
                .foregroundColor(.accentColor)
                .underline()
            
        case .neventMention(let nevent):
            return Text("📝 \(String(nevent.prefix(16)))...")
                .foregroundColor(.accentColor)
                .underline()
            
        case .hashtag(let tag):
            return Text("#\(tag)")
                .foregroundColor(.accentColor)
            
        case .url(let url):
            return Text(url.absoluteString)
                .foregroundColor(.accentColor)
                .underline()
        }
    }
    
    private func parseContent() async {
        guard let ndk = ndkManager.ndk else { return }
        
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
        guard !trackedPubkeys.contains(pubkey),
              let ndk = ndkManager.ndk else { return }
        
        trackedPubkeys.insert(pubkey)
        
        let task = Task {
            let profileStream = await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour)
            
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
}