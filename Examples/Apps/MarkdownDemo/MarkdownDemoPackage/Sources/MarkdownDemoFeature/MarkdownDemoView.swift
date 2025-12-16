import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Interactive demo showcasing NDKSwiftUI's markdown rendering capabilities
public struct MarkdownDemoView: View {
    @State private var selectedDemo = 0
    @State private var enableTapHandlers = true
    @State private var lastTappedItem = ""

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    private let demoCategories = [
        "Basic Formatting",
        "Headings",
        "Lists",
        "Code Blocks",
        "Blockquotes",
        "Nostr Entities",
        "Images",
        "Mixed Content"
    ]

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Demo selector
                Picker("Demo", selection: $selectedDemo) {
                    ForEach(0..<demoCategories.count, id: \.self) { index in
                        Text(demoCategories[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                HStack {
                    Toggle("Tap Handlers", isOn: $enableTapHandlers)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)

                Divider()

                // Content display
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Demo description
                        Text(getDemoDescription())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)

                        // Last tapped item indicator
                        if !lastTappedItem.isEmpty {
                            HStack {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundColor(.blue)
                                Text("Tapped: \(lastTappedItem)")
                                    .font(.caption)
                                Spacer()
                                Button("Clear") {
                                    lastTappedItem = ""
                                }
                                .font(.caption)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }

                        // Rendered markdown using NDKMarkdown
                        renderContent()
                            .padding(.horizontal)

                        // Source markdown
                        DisclosureGroup("View Markdown Source") {
                            Text(currentContent)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Markdown Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func renderContent() -> some View {
        if enableTapHandlers {
            NDKMarkdown(content: currentContent)
                .ndk(ndk)
                .onMentionTap { pubkey in
                    lastTappedItem = "Mention: \(pubkey.prefix(8))..."
                }
                .onHashtagTap { tag in
                    lastTappedItem = "Hashtag: #\(tag)"
                }
                .onLinkTap { url in
                    lastTappedItem = "Link: \(url.absoluteString)"
                }
                .onImageTap { url in
                    lastTappedItem = "Image: \(url.lastPathComponent)"
                }
        } else {
            NDKMarkdown(content: currentContent)
                .ndk(ndk)
        }
    }

    private var currentContent: String {
        return getDemoContent()
    }

    private func getDemoDescription() -> String {
        switch selectedDemo {
        case 0: return "Basic inline formatting: bold, italic, inline code, and links"
        case 1: return "All six heading levels from H1 to H6"
        case 2: return "Ordered and unordered lists with multiple items"
        case 3: return "Code blocks with and without language specification"
        case 4: return "Blockquotes for highlighting quoted text"
        case 5: return "Nostr-specific entities: npubs, notes, and hashtags"
        case 6: return "Inline images with async loading"
        case 7: return "Complex content mixing markdown with Nostr entities"
        default: return ""
        }
    }

    private func getDemoContent() -> String {
        switch selectedDemo {
        case 0: // Basic Formatting
            return """
            This is **bold text** and this is *italic text*.

            You can also use `inline code` for technical terms.

            Here's a [link to Nostr](https://nostr.com) you can click.

            You can combine **bold and *italic* together** too!
            """

        case 1: // Headings
            return """
            # Heading Level 1
            This is the largest heading

            ## Heading Level 2
            Second level heading

            ### Heading Level 3
            Third level heading

            #### Heading Level 4
            Fourth level heading

            ##### Heading Level 5
            Fifth level heading

            ###### Heading Level 6
            Smallest heading level
            """

        case 2: // Lists
            return """
            ## Unordered List

            - First item
            - Second item
            - Third item

            ## Ordered List

            1. First step
            2. Second step
            3. Third step
            4. Fourth step
            """

        case 3: // Code Blocks
            return """
            ## Code Without Language

            ```
            Plain code block
            No syntax highlighting
            ```

            ## Swift Code

            ```swift
            struct User {
                let name: String
                let pubkey: String
            }

            let user = User(name: "Alice", pubkey: "...")
            ```

            ## JavaScript Code

            ```javascript
            const relay = new Relay('wss://relay.nostr.com')
            await relay.connect()
            console.log('Connected!')
            ```
            """

        case 4: // Blockquotes
            return """
            Regular paragraph text here.

            > This is a blockquote. It's typically used for
            > highlighting quoted text or important callouts.

            Another paragraph after the quote.

            > You can **format** text inside blockquotes too!
            """

        case 5: // Nostr Entities
            return """
            ## User Mentions

            Check out nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft

            ## Hashtags

            Popular topics: #nostr #bitcoin #lightning #freedom
            """

        case 6: // Images
            return """
            # Image Rendering Demo

            Here's an image:

            ![Sample Image](https://picsum.photos/400/300)

            You can mix images with other content too!
            """

        case 7: // Mixed Content
            return """
            # Welcome to Nostr!

            **Nostr** is a simple, open protocol that enables global, decentralized, and censorship-resistant social media.

            ## Key Features

            1. **Decentralized** - No central authority
            2. **Censorship-resistant** - Content can't be removed
            3. **Portable identity** - Your identity follows you

            ## Getting Started

            ```swift
            let ndk = NDK(relayURLs: ["wss://relay.damus.io"])
            ```

            > "Nostr is the future of social media"

            Check out these popular tags: #introductions #plebchain #grownostr

            Learn more at [nostr.com](https://nostr.com)
            """

        default:
            return """
            # Default Content

            Select a demo category to see different markdown features!
            """
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MarkdownDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownDemoView(ndk: NDK())
    }
}
#endif
