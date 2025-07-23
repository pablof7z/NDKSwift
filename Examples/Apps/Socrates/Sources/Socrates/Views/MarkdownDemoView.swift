import SwiftUI
import NDKSwift
import NDKSwiftUI

struct MarkdownDemoView: View {
    @EnvironmentObject var ndk: NDK
    
    let sampleContent = """
    # NDKSwift Markdown Demo
    
    This is a **demonstration** of the NDKSwift markdown renderer with *full Nostr entity support*.
    
    ## Features
    
    - **Bold text** and *italic text*
    - `Inline code` support
    - [Links to websites](https://nostr.com)
    - Images: ![Nostr Logo](https://nostr.com/img/logo.png)
    
    ### Nostr Entities
    
    Mentions: @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9
    
    Notes: note1gmtnz6q2m55epmlpe3semjkwtj4av3jvx4emmjsa8g3s9x7tgjsq4tnvj
    
    Events: nevent1qqstkdxwkaq9c59r7xm9de48tnmp0f26dshv37v4avvgjs2urkgklqpz3mhxue69uhhyetvv9ujuerpd46hxtnfdu7n3ft4
    
    ### Hashtags
    
    Popular tags: #nostr #bitcoin #lightning
    
    ## Code Blocks
    
    ```swift
    let ndk = NDK()
    let event = NDKEvent(kind: .text)
    event.content = "Hello Nostr!"
    ```
    
    > This is a blockquote demonstrating how quotes are rendered in the markdown view.
    
    ## Lists
    
    1. First item
    2. Second item
    3. Third item
    
    - Unordered item
    - Another item
    - Final item
    
    ---
    
    That's all for the demo!
    """
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Basic markdown rendering
                GroupBox("Basic Markdown") {
                    NDKMarkdownRenderer(sampleContent, ndk: ndk)
                        .markdownStyle(.minimal)
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
                            print("Tapped Nostr entity: \(entity)")
                        }
                }
                
                // Dark mode style
                GroupBox("Dark Mode Style") {
                    NDKMarkdownRenderer("# Dark Mode\nThis uses the **dark mode** style configuration.", ndk: ndk)
                        .markdownStyle(.dark)
                        .background(Color.black)
                        .environment(\.colorScheme, .dark)
                }
                
                // Nostr style
                GroupBox("Nostr Style") {
                    NDKMarkdownRenderer("Check out #nostr and follow @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9", ndk: ndk)
                        .markdownStyle(.nostr)
                }
                
                // Compact style
                GroupBox("Compact Style") {
                    NDKMarkdownRenderer("""
                    ## Compact Rendering
                    This style has reduced spacing between elements.
                    
                    - Item 1
                    - Item 2
                    - Item 3
                    """, ndk: ndk)
                        .markdownStyle(.compact)
                }
                
                // With images
                GroupBox("With Image Rendering") {
                    NDKMarkdownRenderer("""
                    # Image Support
                    
                    Here's an inline image:
                    ![Example](https://picsum.photos/400/200)
                    
                    And some text after the image.
                    """, ndk: ndk)
                        .renderImages()
                }
                
                // Preview mode
                GroupBox("Preview Mode") {
                    NDKMarkdownPreview(sampleContent, ndk: ndk, previewLines: 5)
                        .markdownStyle(.minimal)
                }
                
                // Entity text only
                GroupBox("Entity Text Renderer") {
                    NDKNostrEntityText(
                        "Follow @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9 for more #nostr content!",
                        ndk: ndk
                    )
                    .font(.headline)
                }
                
                // Custom configuration
                GroupBox("Custom Configuration") {
                    NDKMarkdownRenderer("# Custom Style\nWith **custom colors** and `spacing`.", ndk: ndk)
                        .markdownStyle({
                            var config = MarkdownConfiguration()
                            config.headingColor = .purple
                            config.linkColor = .green
                            config.codeBackgroundColor = .yellow.opacity(0.2)
                            config.mentionColor = .pink
                            config.hashtagColor = .orange
                            return config
                        }())
                }
            }
            .padding()
        }
        .navigationTitle("Markdown Demo")
    }
}

// MARK: - Usage in a Note View

struct NoteWithMarkdownView: View {
    let event: NDKEvent
    @EnvironmentObject var ndk: NDK
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    Text("Author Name")
                        .font(.headline)
                    Text("@\(event.author.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(event.createdAt.formatted())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Markdown content
            NDKMarkdownRenderer(event: event, ndk: ndk)
                .markdownStyle(.minimal)
                .onMentionTap { pubkey in
                    // Navigate to user profile
                }
                .onHashtagTap { tag in
                    // Navigate to hashtag feed
                }
                .onNostrEntityTap { entity in
                    // Handle Nostr entity navigation
                }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationView {
        MarkdownDemoView()
            .environmentObject(NDK())
    }
}