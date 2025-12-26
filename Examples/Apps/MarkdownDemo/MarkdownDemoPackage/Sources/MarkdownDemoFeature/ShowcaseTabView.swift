import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

// MARK: - ShowcaseTabView

/// Showcase tab displaying all renderer variations for each entity type
public struct ShowcaseTabView: View {
    @State private var renderMode: RenderMode = .richText
    @State private var expandedSections: Set<ShowcaseSection> = []
    @State private var sectionContent: [ShowcaseSection: String] = [:]
    @State private var lastTappedItem = ""

    // Event data sources
    @State private var followListDataSource: NDKUIFollowListDataSource?
    @State private var kind1DataSource: NDKSubscription<NDKEvent>?

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Render mode toggle
                    Picker("Mode", selection: $renderMode) {
                        ForEach(RenderMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Sections
                    ForEach(ShowcaseSection.allCases) { section in
                        showcaseSection(section)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Showcase")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom) {
            if !lastTappedItem.isEmpty {
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
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .task {
            followListDataSource = NDKUIFollowListDataSource(
                ndk: ndk,
                pubkey: "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"
            )
        }
        .onChange(of: followListDataSource?.followList) { _, newFollowList in
            guard let followList = newFollowList, !followList.isEmpty else { return }

            kind1DataSource = NDKSubscription(
                ndk: ndk,
                filter: NDKFilter(authors: Array(followList), kinds: [EventKind.textNote])
            )
        }
    }

    // MARK: - Section Rendering

    @ViewBuilder
    private func showcaseSection(_ section: ShowcaseSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand button
            HStack {
                Text("# \(section.rawValue)")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    toggleSection(section)
                } label: {
                    Image(systemName: expandedSections.contains(section)
                        ? "chevron.up.circle.fill"
                        : "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }

            // Collapsible text editor
            if expandedSections.contains(section) {
                TextEditor(text: binding(for: section))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .padding(.vertical, 4)
            }

            // Horizontal scroll of variations
            if shouldShowEventData(section) {
                eventDataSection(section)
            } else {
                rendererVariationsSection(section)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func rendererVariationsSection(_ section: ShowcaseSection) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(RendererStyle.allCases) { style in
                    rendererCard(section: section, style: style)
                }
            }
        }
    }

    @ViewBuilder
    private func eventDataSection(_ section: ShowcaseSection) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Editable content variations
                ForEach(RendererStyle.allCases) { style in
                    rendererCard(section: section, style: style)
                }

                // Live event previews
                if let events = eventsForSection(section) {
                    ForEach(events.prefix(5), id: \.id) { event in
                        eventPreviewCard(event: event, section: section)
                    }
                } else {
                    ProgressView("Loading events...")
                        .frame(width: 280)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func rendererCard(section: ShowcaseSection, style: RendererStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Style label - show article-specific names for kind:30023
            Text(styleLabel(for: style, section: section))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            // Rendered content
            rendererContent(for: section, style: style)
                .frame(width: 280)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        }
    }

    private func styleLabel(for style: RendererStyle, section: ShowcaseSection) -> String {
        if section == .kind30023Articles {
            switch style {
            case .default: return "Hero"
            case .compact: return "Compact"
            case .pill: return "Portrait"
            }
        } else {
            return style.rawValue
        }
    }

    @ViewBuilder
    private func eventPreviewCard(event: NDKEvent, section: ShowcaseSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Event")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                // Author header
                HStack(spacing: 6) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 24)
                    Text(ndk.profile(for: event.pubkey).displayName)
                        .font(.caption)
                }

                // Content preview
                switch renderMode {
                case .richText:
                    DefaultStyleRichText(content: event.content)
                        .ndk(ndk)
                        .lineLimit(6)
                        .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
                case .markdown:
                    DefaultStyleMarkdown(content: event.content, blockConfig: .default)
                        .ndk(ndk)
                        .lineLimit(6)
                        .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
                }
            }
            .frame(width: 280)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }

    // MARK: - Renderer Content

    @ViewBuilder
    private func rendererContent(for section: ShowcaseSection, style: RendererStyle) -> some View {
        let content = sectionContent[section] ?? defaultContent(for: section)

        switch renderMode {
        case .richText:
            richTextRenderer(content: content, style: style, section: section)
        case .markdown:
            markdownRenderer(content: content, style: style, section: section)
        }
    }

    @ViewBuilder
    private func richTextRenderer(content: String, style: RendererStyle, section: ShowcaseSection) -> some View {
        // Use article-specific renderers for kind:30023
        if section == .kind30023Articles {
            switch style {
            case .default:
                ArticleHeroRichText(content: content)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .compact:
                ArticleCompactRichText(content: content)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .pill:
                ArticlePortraitRichText(content: content)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            }
        } else {
            switch style {
            case .default:
                DefaultStyleRichText(content: content)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .compact:
                CompactStyleRichText(content: content)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .pill:
                PillStyleRichText(content: content)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            }
        }
    }

    @ViewBuilder
    private func markdownRenderer(content: String, style: RendererStyle, section: ShowcaseSection) -> some View {
        // Use article-specific renderers for kind:30023
        if section == .kind30023Articles {
            switch style {
            case .default:
                ArticleHeroMarkdown(content: content, blockConfig: .default)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .compact:
                ArticleCompactMarkdown(content: content, blockConfig: .default)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .pill:
                ArticlePortraitMarkdown(content: content, blockConfig: .default)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            }
        } else {
            switch style {
            case .default:
                DefaultStyleMarkdown(content: content, blockConfig: .default)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .compact:
                CompactStyleMarkdown(content: content, blockConfig: .default)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            case .pill:
                PillStyleMarkdown(content: content, blockConfig: .default)
                    .ndk(ndk)
                    .applyTapHandlers(section: section, lastTappedItem: $lastTappedItem)
            }
        }
    }

    // MARK: - Helper Methods

    private func defaultContent(for section: ShowcaseSection) -> String {
        switch section {
        case .mentions:
            return "Hey nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft, thanks for building this amazing library!"
        case .hashtags:
            return "Loving the #nostr ecosystem! #bitcoin #decentralized #freedom"
        case .links:
            return "Check out the docs at https://ndk.fyi for more info. Also visit https://nostr.com and https://github.com/nostr-protocol/nips"
        case .images:
            return """
            Here's a cool image:
            https://blossom.primal.net/f7a062caeb2cb27401b452b2d97b46ed3e7cac97aef86becb60004c4f3c4fca5.jpg
            """
        case .kind1Events:
            return "Here's a note worth checking out:\nnostr:nevent1qgsxu35yyt0mwjjh8pcz4zprhxegz69t4wr9t74vk6zne58wzh0waycppemhxue69uhkummn9ekx7mp0qqsq3zms08nzx3a72cgc0jtsd0g0g9fdx0f9jvp69kp05peuvmrpj5g0w639m"
        case .kind30023Articles:
            return "Check out this article:\nnostr:naddr1qvzqqqr4gupzqmjxss3dld622uu8q25gywum9qtg4w4cv4064jmg20xsac2aam5nqythwumn8ghj7un9d3shjtnswf5k6ctv9ehx2ap0qqxnzd3cx5urjd35xg6rwwpee39928"
        }
    }

    private func toggleSection(_ section: ShowcaseSection) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    private func binding(for section: ShowcaseSection) -> Binding<String> {
        Binding(
            get: { sectionContent[section] ?? defaultContent(for: section) },
            set: { sectionContent[section] = $0 }
        )
    }

    private func eventsForSection(_ section: ShowcaseSection) -> [NDKEvent]? {
        switch section {
        case .kind1Events:
            return kind1DataSource?.data
        default:
            return nil
        }
    }

    private func shouldShowEventData(_ section: ShowcaseSection) -> Bool {
        section == .kind1Events
    }
}

// MARK: - Enums

enum RenderMode: String, CaseIterable {
    case richText = "Rich Text"
    case markdown = "Markdown"
}

enum ShowcaseSection: String, CaseIterable, Identifiable {
    case mentions = "Mentions"
    case hashtags = "Hashtags"
    case links = "Links"
    case images = "Images"
    case kind1Events = "Kind:1 Events"
    case kind30023Articles = "Kind:30023 Articles"

    var id: String { rawValue }
}

// MARK: - Extensions

extension View {
    @ViewBuilder
    func applyTapHandlers(section: ShowcaseSection, lastTappedItem: Binding<String>) -> some View {
        self
            .onMentionTap { pubkey in
                lastTappedItem.wrappedValue = "[\(section.rawValue)] Mention: @\(pubkey.prefix(8))..."
            }
            .onHashtagTap { tag in
                lastTappedItem.wrappedValue = "[\(section.rawValue)] Hashtag: #\(tag)"
            }
            .onLinkTap { url in
                lastTappedItem.wrappedValue = "[\(section.rawValue)] Link: \(url.host ?? url.absoluteString)"
            }
            .onImageTap { url in
                lastTappedItem.wrappedValue = "[\(section.rawValue)] Image: \(url.lastPathComponent)"
            }
            .onEventTap { event in
                lastTappedItem.wrappedValue = "[\(section.rawValue)] Event: \(event.id.prefix(8))..."
            }
    }
}

// MARK: - Preview

#if DEBUG
struct ShowcaseTabView_Previews: PreviewProvider {
    static var previews: some View {
        ShowcaseTabView(ndk: NDK())
    }
}
#endif
