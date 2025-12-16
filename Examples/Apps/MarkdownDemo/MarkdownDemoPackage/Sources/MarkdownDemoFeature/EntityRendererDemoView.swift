import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Advanced demo allowing per-entity-type renderer selection
public struct EntityRendererDemoView: View {
    @State private var imageRenderer = ImageRendererType.placeholder
    @State private var mentionRenderer = MentionRendererType.inline
    @State private var eventRenderer = EventRendererType.reference
    @State private var linkRenderer = LinkRendererType.simple
    @State private var hashtagRenderer = HashtagRendererType.highlighted
    @State private var codeBlockRenderer = CodeBlockRendererType.standard
    @State private var lastTappedItem = ""
    @State private var editableContent: String

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        self._editableContent = State(initialValue: Self.defaultContent)
    }

    enum ImageRendererType: String, CaseIterable {
        case none = "None (raw URL)"
        case placeholder = "Placeholder (🖼)"
        case asyncImage = "Async Image"
        case fullImage = "Full Image with Zoom"
    }

    enum MentionRendererType: String, CaseIterable {
        case none = "None (raw npub)"
        case inline = "Inline (@user)"
        case highlighted = "Highlighted"
        case profileCard = "Profile Card"
    }

    enum EventRendererType: String, CaseIterable {
        case none = "None (raw note/nevent)"
        case reference = "Reference (note1...)"
        case quote = "Quote Card"
        case preview = "Event Preview"
    }

    enum LinkRendererType: String, CaseIterable {
        case none = "None (raw URL)"
        case simple = "Simple Link"
        case preview = "Link Preview"
        case button = "Button Style"
    }

    enum HashtagRendererType: String, CaseIterable {
        case none = "None (raw #tag)"
        case plain = "Plain Text"
        case highlighted = "Highlighted #tag"
        case chip = "Chip Style"
    }

    enum CodeBlockRendererType: String, CaseIterable {
        case none = "None (raw code)"
        case standard = "Standard"
        case themed = "Syntax Themed"
        case minimal = "Minimal"
    }

    public var body: some View {
        TabView {
            // Preview Tab
            NavigationView {
                renderContent()
                    .navigationTitle("Preview")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Preview", systemImage: "eye")
            }

            // Edit Tab
            NavigationView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Edit Markdown")
                            .font(.headline)
                        Spacer()
                        Button("Reset") {
                            editableContent = Self.defaultContent
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()

                    TextEditor(text: $editableContent)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                }
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Edit", systemImage: "pencil")
            }

            // Settings Tab
            NavigationView {
                List {
                    Section("Entity Renderers") {
                        rendererPicker("Images:", selection: $imageRenderer)
                        rendererPicker("Mentions:", selection: $mentionRenderer)
                        rendererPicker("Events:", selection: $eventRenderer)
                        rendererPicker("Links:", selection: $linkRenderer)
                        rendererPicker("Hashtags:", selection: $hashtagRenderer)
                        rendererPicker("Code Blocks:", selection: $codeBlockRenderer)
                    }

                    if !lastTappedItem.isEmpty {
                        Section("Last Tapped") {
                            HStack {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundColor(.blue)
                                Text(lastTappedItem)
                                    .font(.caption)
                                Spacer()
                                Button("Clear") {
                                    lastTappedItem = ""
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    @ViewBuilder
    private func rendererPicker<T: RawRepresentable & CaseIterable & Hashable>(
        _ label: String,
        selection: Binding<T>
    ) -> some View where T.RawValue == String {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 90, alignment: .leading)

            Picker("", selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func renderContent() -> some View {
        // Use custom renderer based on settings
        CustomEntityRenderer(
            content: editableContent,
            ndk: ndk,
            style: MarkdownConfiguration(),
            imageRenderer: imageRenderer,
            mentionRenderer: mentionRenderer,
            eventRenderer: eventRenderer,
            linkRenderer: linkRenderer,
            hashtagRenderer: hashtagRenderer,
            codeBlockRenderer: codeBlockRenderer,
            onTap: { item in
                lastTappedItem = item
            }
        )
    }

    private static let defaultContent = """
        Just discovered this amazing Nostr library! 🚀

        Check out the docs at https://ndk.fyi for more info.

        Special thanks to nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft for building this!

        #nostr #bitcoin #decentralized

        Here's a cool image to go with it:
        https://r2a.primal.net/uploads2/d/f3/bd/df3bdd118f7db2cdf57821f958033db07dfd9de72248e6869734cbb9e2e8c130.png

        This is an article:
        nostr:naddr1qvzqqqr4gupzqmjxss3dld622uu8q25gywum9qtg4w4cv4064jmg20xsac2aam5nqythwumn8ghj7un9d3shjtnswf5k6ctv9ehx2ap0qqxnzd3cx5urjd35xg6rwwpee39928

        And here's a note worth checking out:
        nostr:nevent1qgsxu35yyt0mwjjh8pcz4zprhxegz69t4wr9t74vk6zne58wzh0waycppemhxue69uhkummn9ekx7mp0qqsq3zms08nzx3a72cgc0jtsd0g0g9fdx0f9jvp69kp05peuvmrpj5g0w639m
        """
}

// MARK: - Custom Entity Renderer

@MainActor
struct CustomEntityRenderer: View {
    let content: String
    nonisolated(unsafe) let ndk: NDK
    let style: MarkdownConfiguration
    let imageRenderer: EntityRendererDemoView.ImageRendererType
    let mentionRenderer: EntityRendererDemoView.MentionRendererType
    let eventRenderer: EntityRendererDemoView.EventRendererType
    let linkRenderer: EntityRendererDemoView.LinkRendererType
    let hashtagRenderer: EntityRendererDemoView.HashtagRendererType
    let codeBlockRenderer: EntityRendererDemoView.CodeBlockRendererType
    let onTap: (String) -> Void

    @State private var parsedContent: NDKParsedContent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let parsed = parsedContent {
                    renderGroupedComponents(parsed.components)
                } else {
                    Text(content)
                }
            }
            .padding()
        }
        .task(id: content) {
            parsedContent = await ndk.parseContent(content)
        }
    }

    @ViewBuilder
    private func renderGroupedComponents(_ components: [NDKParsedContent.Component]) -> some View {
        let groups = groupComponents(components)

        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            switch group {
            case .inline(let inlineComponents):
                renderInlineComponents(inlineComponents)
            case .block(let component):
                renderComponent(component)
            }
        }
    }

    private enum ComponentGroup {
        case inline([NDKParsedContent.Component])
        case block(NDKParsedContent.Component)
    }

    private func groupComponents(_ components: [NDKParsedContent.Component]) -> [ComponentGroup] {
        var groups: [ComponentGroup] = []
        var currentInlineGroup: [NDKParsedContent.Component] = []

        for component in components {
            if isBlockComponent(component) {
                // Flush current inline group
                if !currentInlineGroup.isEmpty {
                    groups.append(.inline(currentInlineGroup))
                    currentInlineGroup = []
                }
                // Add block component
                groups.append(.block(component))
            } else {
                // Accumulate inline component
                currentInlineGroup.append(component)
            }
        }

        // Flush remaining inline components
        if !currentInlineGroup.isEmpty {
            groups.append(.inline(currentInlineGroup))
        }

        return groups
    }

    private func isBlockComponent(_ component: NDKParsedContent.Component) -> Bool {
        switch component {
        case .url(let url):
            return isImageURL(url) || linkRenderer == .preview
        case .noteMention, .neventMention, .eventMention:
            return eventRenderer == .quote || eventRenderer == .preview
        default:
            return false
        }
    }

    @ViewBuilder
    private func renderInlineComponents(_ components: [NDKParsedContent.Component]) -> some View {
        components.reduce(Text("")) { result, component in
            result + renderInlineComponent(component)
        }
    }

    private func renderInlineComponent(_ component: NDKParsedContent.Component) -> Text {
        switch component {
        case .text(let text):
            return Text(text)
                .font(style.bodyFont)
                .foregroundColor(style.textColor)

        case .userMention(let pubkey, _):
            return renderInlineMention(pubkey: pubkey)

        case .hashtag(let tag):
            return renderInlineHashtag(tag)

        case .url(let url):
            if isImageURL(url) {
                // Image URL - only show inline if image renderer is .none
                if imageRenderer == .none {
                    return Text(url.absoluteString)
                }
                return Text("")
            } else {
                // Regular link
                if linkRenderer == .none {
                    return Text(url.absoluteString)
                } else if linkRenderer != .preview {
                    return Text(url.absoluteString)
                        .foregroundColor(style.linkColor)
                        .underline()
                }
                return Text("")
            }

        case .noteMention(let note):
            if eventRenderer == .none {
                return Text("nostr:\(note)")
            } else if eventRenderer == .reference {
                return Text("📝 \(note.prefix(16))...")
                    .foregroundColor(style.nostrEntityColor)
            }
            return Text("")

        case .neventMention(let nevent):
            if eventRenderer == .none {
                return Text("nostr:\(nevent)")
            } else if eventRenderer == .reference {
                return Text("📝 \(nevent.prefix(16))...")
                    .foregroundColor(style.nostrEntityColor)
            }
            return Text("")

        case .eventMention(let eventId):
            if eventRenderer == .none {
                return Text(eventId)
            } else if eventRenderer == .reference {
                return Text("📝 \(eventId.prefix(8))...")
                    .foregroundColor(style.nostrEntityColor)
            }
            return Text("")

        case .nprofileMention(let nprofile):
            return Text("@\(nprofile.prefix(16))...")
                .foregroundColor(style.mentionColor)
        }
    }

    private func renderInlineMention(pubkey: String) -> Text {
        switch mentionRenderer {
        case .none:
            // Show raw npub format
            if let npub = try? String.toNpub(pubkey) {
                return Text("nostr:\(npub)")
            }
            return Text(pubkey)
        case .inline:
            // For inline mode, just show @username without components
            return Text("@\(pubkey.prefix(8))...")
                .foregroundColor(style.mentionColor)
        case .highlighted:
            return Text("@\(pubkey.prefix(8))...")
                .font(style.mentionFont)
                .foregroundColor(style.mentionColor)
        case .profileCard:
            // For profile card in inline context, use icon + name
            return Text("👤 @\(pubkey.prefix(8))...")
                .foregroundColor(style.mentionColor)
        }
    }

    private func renderInlineHashtag(_ tag: String) -> Text {
        switch hashtagRenderer {
        case .none:
            return Text("#\(tag)")
        case .plain:
            return Text("#\(tag)")
                .foregroundColor(style.textColor)
        case .highlighted, .chip:
            return Text("#\(tag)")
                .foregroundColor(style.hashtagColor)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func renderComponent(_ component: NDKParsedContent.Component) -> some View {
        switch component {
        case .text(let text):
            Text(text)
                .font(style.bodyFont)
                .foregroundColor(style.textColor)

        case .userMention(let pubkey, let npub):
            renderMention(pubkey: pubkey, npub: npub)

        case .hashtag(let tag):
            renderHashtag(tag)

        case .url(let url):
            renderURL(url)

        case .noteMention(let note), .neventMention(let note):
            renderEventReference(note)

        case .eventMention(let eventId):
            renderEventReference(eventId)

        case .nprofileMention(let nprofile):
            Text("@\(nprofile.prefix(16))...")
                .foregroundColor(style.mentionColor)
        }
    }

    @ViewBuilder
    private func renderMention(pubkey: String, npub: String) -> some View {
        switch mentionRenderer {
        case .none:
            Text("nostr:\(npub)")
        case .inline:
            NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                .foregroundColor(style.mentionColor)
                .onTapGesture {
                    onTap("Mention: @\(pubkey.prefix(8))... (Inline)")
                }
        case .highlighted:
            NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                .font(style.mentionFont)
                .foregroundColor(style.mentionColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(style.mentionColor.opacity(0.15))
                .cornerRadius(4)
                .onTapGesture {
                    onTap("Mention: @\(pubkey.prefix(8))... (Highlighted)")
                }
        case .profileCard:
            // For profile card, show name with profile picture
            HStack(spacing: 8) {
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 24)
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                    .foregroundColor(style.mentionColor)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .onTapGesture {
                onTap("Mention: @\(pubkey.prefix(8))... (Profile Card)")
            }
        }
    }

    @ViewBuilder
    private func renderHashtag(_ tag: String) -> some View {
        switch hashtagRenderer {
        case .none:
            Text("#\(tag)")
        case .plain:
            Text("#\(tag)")
                .foregroundColor(style.textColor)
        case .highlighted:
            Text("#\(tag)")
                .foregroundColor(style.hashtagColor)
                .fontWeight(.medium)
                .onTapGesture {
                    onTap("Hashtag: #\(tag) (Highlighted)")
                }
        case .chip:
            Text("#\(tag)")
                .font(.caption)
                .foregroundColor(style.hashtagColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(style.hashtagColor.opacity(0.15))
                .cornerRadius(12)
                .onTapGesture {
                    onTap("Hashtag: #\(tag) (Chip)")
                }
        }
    }

    @ViewBuilder
    private func renderURL(_ url: URL) -> some View {
        // Check if it's an image URL
        if isImageURL(url) {
            renderImage(url)
        } else {
            renderLink(url)
        }
    }

    @ViewBuilder
    private func renderImage(_ url: URL) -> some View {
        switch imageRenderer {
        case .none:
            Text(url.absoluteString)
        case .placeholder:
            Text("🖼")
                .font(.largeTitle)
        case .asyncImage:
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
            } placeholder: {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
            }
        case .fullImage:
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
            } placeholder: {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func renderLink(_ url: URL) -> some View {
        switch linkRenderer {
        case .none:
            Text(url.absoluteString)
        case .simple:
            Link(url.absoluteString, destination: url)
                .foregroundColor(style.linkColor)
                .onTapGesture {
                    onTap("Link: \(url.absoluteString) (Simple)")
                }
        case .preview:
            NDKUIURLPreview(url: url, style: .compact)
        case .button:
            Button(action: {
                onTap("Link: \(url.absoluteString) (Button)")
            }) {
                Text(url.host ?? url.absoluteString)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(style.linkColor.opacity(0.15))
                    .foregroundColor(style.linkColor)
                    .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func renderEventReference(_ reference: String) -> some View {
        switch eventRenderer {
        case .none:
            Text("nostr:\(reference)")
        case .reference:
            Text("📝 \(reference.prefix(16))...")
                .foregroundColor(style.nostrEntityColor)
                .onTapGesture {
                    onTap("Event: \(reference.prefix(8))... (Reference)")
                }
        case .quote, .preview:
            // Extract event ID and show preview
            if let eventId = try? Bech32.eventId(from: reference) {
                NDKUIEventPreview(ndk: ndk, eventReference: .eventId(eventId))
            } else {
                Text("📝 \(reference.prefix(16))...")
                    .foregroundColor(style.nostrEntityColor)
            }
        }
    }

    private func isImageURL(_ url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Preview

#if DEBUG
struct EntityRendererDemoView_Previews: PreviewProvider {
    static var previews: some View {
        EntityRendererDemoView(ndk: NDK())
    }
}
#endif
