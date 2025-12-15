# Markdown Rendering Examples

This guide demonstrates how to use NDKSwiftUI's markdown rendering capabilities in your Nostr applications.

## Basic Usage

The simplest way to render markdown content:

```swift
import SwiftUI
import NDKSwift
import NDKSwiftUI

struct ContentView: View {
    @EnvironmentObject var ndk: NDK
    let content = "# Hello Nostr\nThis is **bold** and this is *italic*."

    var body: some View {
        NDKUIMarkdownRenderer(content, ndk: ndk)
    }
}
```

## Rendering Event Content

When displaying Nostr events, you can render their content as markdown:

```swift
struct EventView: View {
    let event: NDKEvent
    @EnvironmentObject var ndk: NDK
    
    var body: some View {
        VStack(alignment: .leading) {
            // Author info
            HStack {
                NDKProfilePicture(pubkey: event.author)
                NDKDisplayName(pubkey: event.author)
                Spacer()
                NDKRelativeTime(date: event.createdAt)
            }
            
            // Markdown content
            NDKUIMarkdownRenderer(event: event, ndk: ndk)
                .markdownStyle(.minimal)
        }
        .padding()
    }
}
```

## Handling Nostr Entities

The markdown renderer automatically detects and makes Nostr entities interactive:

```swift
struct InteractiveContentView: View {
    @EnvironmentObject var ndk: NDK
    let content = """
    Check out @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9
    
    See this note: note1gmtnz6q2m55epmlpe3semjkwtj4av3jvx4emmjsa8g3s9x7tgjsq4tnvj
    
    Popular tags: #nostr #bitcoin #lightning
    """
    
    var body: some View {
        NDKUIMarkdownRenderer(content, ndk: ndk)
            .onMentionTap { pubkey in
                print("Tapped mention: \(pubkey)")
                // Navigate to user profile
            }
            .onHashtagTap { tag in
                print("Tapped hashtag: \(tag)")
                // Navigate to hashtag feed
            }
            .onNostrEntityTap { entity in
                switch entity {
                case .npub(let pubkey), .nprofile(let pubkey):
                    print("Navigate to profile: \(pubkey)")
                case .note(let id), .nevent(let id):
                    print("Navigate to note: \(id)")
                default:
                    break
                }
            }
    }
}
```

## Styling Options

### Using Predefined Styles

```swift
struct StyledMarkdownView: View {
    @EnvironmentObject var ndk: NDK
    let content: String
    
    var body: some View {
        VStack(spacing: 20) {
            // Minimal style (default)
            NDKUIMarkdownRenderer(content, ndk: ndk)
                .markdownStyle(.minimal)
            
            // Dark mode optimized
            NDKUIMarkdownRenderer(content, ndk: ndk)
                .markdownStyle(.dark)
                .background(Color.black)
            
            // Nostr-themed
            NDKUIMarkdownRenderer(content, ndk: ndk)
                .markdownStyle(.nostr)
            
            // Compact spacing
            NDKUIMarkdownRenderer(content, ndk: ndk)
                .markdownStyle(.compact)
        }
    }
}
```

### Custom Styling

```swift
struct CustomStyledView: View {
    @EnvironmentObject var ndk: NDK
    
    var customStyle: MarkdownConfiguration {
        var config = MarkdownConfiguration()
        
        // Custom colors
        config.headingColor = .purple
        config.linkColor = .green
        config.mentionColor = .orange
        config.hashtagColor = .pink
        config.codeBackgroundColor = .blue.opacity(0.1)
        
        // Custom fonts
        config.h1Font = .system(size: 32, weight: .black)
        config.bodyFont = .system(size: 16)
        config.codeFont = .system(size: 14, design: .monospaced)
        
        // Custom spacing
        config.paragraphSpacing = 16
        config.listItemSpacing = 8
        
        // Custom bullet
        config.bulletCharacter = "→"
        
        return config
    }
    
    var body: some View {
        NDKUIMarkdownRenderer(
            "# Custom Styled\nWith **custom** colors and fonts!",
            ndk: ndk
        )
        .markdownStyle(customStyle)
    }
}
```

## Image Rendering

Enable inline image rendering for markdown images:

```swift
struct ImageMarkdownView: View {
    @EnvironmentObject var ndk: NDK
    let content = """
    # Image Example
    
    Here's an inline image:
    ![Nostr Logo](https://nostr.com/logo.png)
    
    And here's another one:
    ![Example](https://example.com/image.jpg)
    """
    
    var body: some View {
        NDKUIMarkdownRenderer(content, ndk: ndk)
            .renderImages()
            .onImageTap { url in
                print("Tapped image: \(url)")
                // Show full screen image viewer
            }
    }
}
```

## Preview Mode

Show a truncated preview with expand functionality:

```swift
struct PreviewableContentView: View {
    @EnvironmentObject var ndk: NDK
    let longContent: String // Long markdown content
    
    var body: some View {
        NDKMarkdownPreview(
            longContent,
            ndk: ndk,
            previewLines: 5
        )
        .markdownStyle(.minimal)
    }
}
```

## Advanced: Code Syntax Highlighting

The renderer supports code blocks with language hints:

```swift
struct CodeExampleView: View {
    @EnvironmentObject var ndk: NDK
    let content = """
    # Code Examples
    
    Here's some Swift code:
    
    ```swift
    let ndk = NDK()
    let event = NDKEvent(kind: .text)
    event.content = "Hello Nostr!"
    try await ndk.publish(event)
    ```
    
    And some JavaScript:
    
    ```javascript
    const relay = new Relay('wss://relay.nostr.com')
    await relay.connect()
    ```
    """
    
    var body: some View {
        NDKUIMarkdownRenderer(content, ndk: ndk)
            .markdownStyle(.minimal)
    }
}
```

## Complete Example: Note Composer Preview

```swift
struct NoteComposerView: View {
    @EnvironmentObject var ndk: NDK
    @State private var noteContent = ""
    @State private var showPreview = false
    
    var body: some View {
        VStack {
            // Composer
            TextEditor(text: $noteContent)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                )
            
            // Preview toggle
            Toggle("Show Preview", isOn: $showPreview)
                .padding(.horizontal)
            
            if showPreview {
                Divider()
                
                // Live preview
                ScrollView {
                    NDKUIMarkdownRenderer(noteContent, ndk: ndk)
                        .markdownStyle(.minimal)
                        .padding()
                }
            }
            
            // Post button
            Button(action: postNote) {
                Text("Post")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
    
    func postNote() {
        Task {
            let event = NDKEvent(kind: .text)
            event.content = noteContent
            try await ndk.publish(event)
        }
    }
}
```

## Performance Considerations

1. **Large Documents**: For very large markdown documents, consider using preview mode initially
2. **Image Loading**: Use `.renderImages()` selectively as it can impact scrolling performance
3. **Syntax Highlighting**: Code blocks with syntax highlighting may impact performance for large code snippets

## Supported Markdown Features

- **Headings**: `# H1` through `###### H6`
- **Emphasis**: `*italic*` or `_italic_`, `**bold**`
- **Code**: `` `inline code` `` and ``` code blocks ```
- **Lists**: `- item` or `1. item` (including nested lists)
- **Blockquotes**: `> quote`
- **Links**: `[text](url)`
- **Images**: `![alt](url)`
- **Horizontal rules**: `---` or `***`

## Nostr-Specific Features

- **Mentions**: `@npub...` or `@user`
- **Note references**: `note1...` or `nevent1...`
- **Hashtags**: `#topic`
- **Profile references**: `nprofile1...`
- **Address references**: `naddr1...`

All Nostr entities are automatically detected and made interactive.