import SwiftUI
import NDKSwift

struct ArticleView: View {
    let article: Article
    @EnvironmentObject var appState: AppState
    @State private var selectedText: String?
    @State private var showHighlightOptions = false
    @State private var highlightRange: NSRange?
    @State private var author: NDKUserProfile?
    @State private var isBookmarked = false
    @State private var showShareSheet = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Image
                    if let imageURL = article.image, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 250)
                                    .clipped()
                            case .failure(_):
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 250)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    }
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 250)
                                    .shimmer()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: .spacingM) {
                        // Title and metadata
                        VStack(alignment: .leading, spacing: .spacingS) {
                            Text(article.title)
                                .font(.highlighterTitle)
                                .foregroundColor(.highlighterText)
                            
                            HStack(spacing: .spacingM) {
                                // Author
                                HStack(spacing: .spacingXS) {
                                    Circle()
                                        .fill(Color.highlighterPurple.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if let picture = author?.picture, let url = URL(string: picture) {
                                                AsyncImage(url: url) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .clipShape(Circle())
                                                } placeholder: {
                                                    Image(systemName: "person.fill")
                                                        .foregroundColor(.highlighterPurple)
                                                }
                                            } else {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.highlighterPurple)
                                            }
                                        }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(author?.displayName ?? formatPubkey(article.author))
                                            .font(.highlighterCaption)
                                            .fontWeight(.medium)
                                        
                                        if let publishedAt = article.publishedAt {
                                            Text(publishedAt.formatted(.relative(presentation: .named)))
                                                .font(.highlighterCaption2)
                                                .foregroundColor(.highlighterSecondaryText)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // Reading time
                                Label("\(article.estimatedReadingTime) min", systemImage: "clock")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterSecondaryText)
                            }
                        }
                        .padding(.horizontal, .spacingL)
                        .padding(.top, .spacingL)
                        
                        if let summary = article.summary {
                            Text(summary)
                                .font(.highlighterBody)
                                .foregroundColor(.highlighterSecondaryText)
                                .padding(.horizontal, .spacingL)
                        }
                        
                        // Tags
                        if !article.hashtags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: .spacingS) {
                                    ForEach(article.hashtags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.highlighterCaption)
                                            .foregroundColor(.highlighterPurple)
                                            .padding(.horizontal, .spacingM)
                                            .padding(.vertical, .spacingXS)
                                            .background(
                                                Capsule()
                                                    .fill(Color.highlighterPurple.opacity(0.1))
                                            )
                                    }
                                }
                                .padding(.horizontal, .spacingL)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, .spacingL)
                        
                        // Article Content with highlight support
                        MarkdownView(
                            content: article.content,
                            onTextSelected: { text, range in
                                selectedText = text
                                highlightRange = range
                                showHighlightOptions = true
                                HapticType.selection.trigger()
                            }
                        )
                        .padding(.horizontal, .spacingL)
                        .padding(.bottom, .spacingXL)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: .spacingM) {
                        Button(action: { 
                            isBookmarked.toggle()
                            HapticType.light.trigger()
                        }) {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .foregroundColor(.highlighterPurple)
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.highlighterPurple)
                        }
                    }
                }
            }
            .sheet(isPresented: $showHighlightOptions) {
                if let text = selectedText {
                    HighlightOptionsSheet(
                        selectedText: text,
                        articleTitle: article.title,
                        articleUrl: "nostr:\(article.id)",
                        onHighlight: { comment in
                            Task {
                                await createHighlight(text: text, comment: comment)
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ArticleShareSheet(items: [
                    "Check out this article: \(article.title)",
                    "nostr:\(article.id)"
                ])
            }
        }
        .task {
            await loadAuthor()
        }
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
    
    private func loadAuthor() async {
        guard let ndk = appState.ndk else { return }
        
        // Load individual profile using declarative data source
        let profileDataSource = ndk.observe(
            filter: NDKFilter(
                authors: [article.author],
                kinds: [0]
            ),
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in profileDataSource.events {
            if let fetchedProfile = JSONCoding.safeDecode(NDKUserProfile.self, from: event.content) {
                await MainActor.run {
                    self.author = fetchedProfile
                }
                break
            }
        }
    }
    
    private func createHighlight(text: String, comment: String?) async {
        guard let ndk = appState.ndk,
              let signer = appState.activeSigner else { return }
        
        do {
            var tags: [[String]] = []
            
            // Add context tag
            tags.append(["context", text.trimmingCharacters(in: .whitespacesAndNewlines)])
            
            // Add article reference (a tag for replaceable event)
            if let identifier = article.identifier {
                tags.append(["a", "30023:\(article.author):\(identifier)"])
            }
            
            // Add alt tag
            tags.append(["alt", "Highlight: '\(text.prefix(50))...'"])
            
            // Create highlight event
            let highlightContent = comment ?? text
            let event = try await NDKEventBuilder(ndk: ndk)
                .kind(9802)
                .content(highlightContent)
                .tags(tags)
                .build(signer: signer)
            
            _ = try await ndk.publish(event)
            
            await MainActor.run {
                showHighlightOptions = false
                selectedText = nil
                HapticType.success.trigger()
            }
        } catch {
            print("Failed to create highlight: \(error)")
            HapticType.error.trigger()
        }
    }
}

// MARK: - Markdown View

struct MarkdownView: UIViewRepresentable {
    let content: String
    let onTextSelected: (String, NSRange) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        
        // Configure text styling
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        style.paragraphSpacing = 16
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style
        ]
        
        // Simple markdown parsing (basic implementation)
        let attributedText = parseMarkdown(content, baseAttributes: attributes)
        textView.attributedText = attributedText
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTextSelected: onTextSelected)
    }
    
    private func parseMarkdown(_ text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        
        // Bold text
        let boldPattern = "\\*\\*(.*?)\\*\\*"
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = boldRegex.matches(in: text, range: NSRange(location: 0, length: text.count))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: text) {
                    let boldText = String(text[range])
                    result.replaceCharacters(
                        in: match.range,
                        with: NSAttributedString(
                            string: boldText,
                            attributes: baseAttributes.merging([.font: UIFont.boldSystemFont(ofSize: 17)]) { $1 }
                        )
                    )
                }
            }
        }
        
        // Italic text
        let italicPattern = "\\*(.*?)\\*"
        if let italicRegex = try? NSRegularExpression(pattern: italicPattern) {
            let matches = italicRegex.matches(in: result.string, range: NSRange(location: 0, length: result.string.count))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: result.string) {
                    let italicText = String(result.string[range])
                    result.replaceCharacters(
                        in: match.range,
                        with: NSAttributedString(
                            string: italicText,
                            attributes: baseAttributes.merging([.font: UIFont.italicSystemFont(ofSize: 17)]) { $1 }
                        )
                    )
                }
            }
        }
        
        return result
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let onTextSelected: (String, NSRange) -> Void
        
        init(onTextSelected: @escaping (String, NSRange) -> Void) {
            self.onTextSelected = onTextSelected
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange,
                  !selectedRange.isEmpty,
                  let selectedText = textView.text(in: selectedRange),
                  !selectedText.isEmpty else { return }
            
            let location = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
            let length = textView.offset(from: selectedRange.start, to: selectedRange.end)
            let range = NSRange(location: location, length: length)
            
            onTextSelected(selectedText, range)
        }
    }
}

// MARK: - Highlight Options Sheet

struct HighlightOptionsSheet: View {
    let selectedText: String
    let articleTitle: String
    let articleUrl: String
    let onHighlight: (String?) -> Void
    @State private var comment = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .spacingL) {
                VStack(alignment: .leading, spacing: .spacingS) {
                    Text("Selected Text")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                    
                    Text("\"\(selectedText)\"")
                        .font(.highlighterQuote)
                        .foregroundColor(.highlighterText)
                        .padding()
                        .background(Color.highlighterOrange.opacity(0.1))
                        .cornerRadius(12)
                }
                
                VStack(alignment: .leading, spacing: .spacingS) {
                    Text("Add a comment (optional)")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                    
                    TextField("Your thoughts...", text: $comment, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }
                
                Spacer()
                
                VStack(spacing: .spacingM) {
                    Button(action: {
                        onHighlight(comment.isEmpty ? nil : comment)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "highlighter")
                            Text("Create Highlight")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Share Sheet

struct ArticleShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ArticleView(article: try! Article(
        from: NDKEvent(
            id: "test",
            pubkey: "test",
            createdAt: 0,
            kind: 30023,
            tags: [
                ["title", "Sample Article"],
                ["summary", "This is a sample article for preview"],
                ["published_at", "1234567890"]
            ],
            content: "# Sample Article\n\nThis is some **bold** text and some *italic* text.\n\nLorem ipsum dolor sit amet.",
            sig: ""
        )
    ))
    .environmentObject(AppState())
}