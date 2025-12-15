import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Interactive demo showcasing NDKSwiftUI's markdown rendering capabilities
struct MarkdownDemoView: View {
    @State private var selectedDemo = 0
    @State private var selectedStyle = 0
    @State private var customContent = defaultMarkdown

    let ndk: NDK

    init(ndk: NDK) {
        self.ndk = ndk
    }

    private let demoCategories = [
        "Basic Formatting",
        "Headings",
        "Lists",
        "Code Blocks",
        "Blockquotes",
        "Nostr Entities",
        "Mixed Content",
        "Custom Input"
    ]

    private let styles = [
        ("Default", MarkdownConfiguration()),
        ("Minimal", .minimal),
        ("Dark", .dark),
        ("Nostr", .nostr),
        ("Compact", .compact)
    ]

    var body: some View {
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

                // Style selector
                HStack {
                    Text("Style:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Style", selection: $selectedStyle) {
                        ForEach(0..<styles.count, id: \.self) { index in
                            Text(styles[index].0).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
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

                        // Rendered markdown
                        NDKUIMarkdownRenderer(currentContent, ndk: ndk)
                            .markdownStyle(styles[selectedStyle].1)
                            .onMentionTap { pubkey in
                                print("Tapped mention: \(pubkey)")
                            }
                            .onHashtagTap { tag in
                                print("Tapped hashtag: \(tag)")
                            }
                            .onLinkTap { url in
                                print("Tapped link: \(url)")
                            }
                            .onNostrEntityTap { entity in
                                print("Tapped entity: \(entity)")
                            }

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

    private var currentContent: String {
        if selectedDemo == 7 {
            return customContent
        }
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
        case 6: return "Complex content mixing markdown with Nostr entities"
        case 7: return "Edit the markdown below to test custom content"
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
            * Alternative marker
            + Another marker

            ## Ordered List

            1. First step
            2. Second step
            3. Third step
            4. Fourth step

            ## Mixed Lists

            1. First ordered item
            2. Second ordered item
            - Unordered sub-item
            - Another sub-item
            3. Third ordered item
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
            > *Italic* and `code` also work.
            """

        case 5: // Nostr Entities
            return """
            ## User Mentions

            Check out @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9

            ## Event References

            See this note: note1gmtnz6q2m55epmlpe3semjkwtj4av3jvx4emmjsa8g3s9x7tgjsq4tnvj

            ## Hashtags

            Popular topics: #nostr #bitcoin #lightning #freedom

            ## Simple Mentions

            Hello @alice and @bob! Join us at #meetup
            """

        case 6: // Mixed Content
            return """
            # Welcome to Nostr! ⚡

            **Nostr** is a simple, open protocol that enables global, decentralized, and censorship-resistant social media.

            ## Key Features

            1. **Decentralized** - No central authority
            2. **Censorship-resistant** - Content can't be removed
            3. **Portable identity** - Your identity follows you

            ## Getting Started

            To join Nostr, you'll need:

            ```
            1. Generate a keypair (npub/nsec)
            2. Choose a client
            3. Connect to relays
            ```

            > "Nostr is the future of social media"
            > - @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9

            Check out these popular tags:
            - #introductions
            - #plebchain
            - #grownostr

            Learn more at [nostr.com](https://nostr.com)
            """

        default:
            return customContent
        }
    }

    private static let defaultMarkdown = """
    # Edit This Content

    Try changing this markdown to see how it renders!

    - Add your own **formatting**
    - Use *different* styles
    - Include `code` snippets

    ```swift
    // Add your own code examples
    func hello() {
        print("Hello, Nostr!")
    }
    ```

    > Add quotes and other content

    Try adding #hashtags and @mentions too!
    """
}

// MARK: - Preview

#if DEBUG
struct MarkdownDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownDemoView(ndk: NDK())
    }
}
#endif
