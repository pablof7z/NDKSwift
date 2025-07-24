import SwiftUI
import NDKSwift

struct HighlightDetailView: View {
    let highlight: HighlightEvent
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var isZapped = false
    @State private var showShareSheet = false
    @State private var showReplyComposer = false
    @State private var replyText = ""
    @State private var author: NDKUserProfile?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Highlight content
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\"\(highlight.content)\"")
                            .font(.highlighterQuote)
                            .foregroundColor(.highlighterText)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.highlighterPurple.opacity(0.1),
                                        Color.highlighterOrange.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                        
                        // Context if available
                        if let context = highlight.context {
                            Text(context)
                                .font(.highlighterBody)
                                .foregroundColor(.highlighterSecondaryText)
                                .padding(.horizontal)
                        }
                        
                        // Author's comment if available
                        if let comment = highlight.comment {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Author's Note", systemImage: "bubble.left.fill")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterPurple)
                                
                                Text(comment)
                                    .font(.highlighterBody)
                                    .foregroundColor(.highlighterText)
                            }
                            .padding()
                            .background(Color.highlighterCardBackground)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Author info
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.highlighterPurple)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(author?.name ?? author?.displayName ?? "Anonymous")
                                .font(.highlighterBody)
                                .fontWeight(.medium)
                            
                            Text(relativeTime(from: highlight.createdAt))
                                .font(.highlighterCaption)
                                .foregroundColor(.highlighterSecondaryText)
                        }
                        
                        Spacer()
                        
                        // Follow button
                        Button(action: followAuthor) {
                            Text("Follow")
                                .font(.highlighterCaption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.highlighterPurple)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Source link
                    if let url = highlight.url {
                        Link(destination: URL(string: url)!) {
                            HStack {
                                Image(systemName: "link.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.highlighterPurple)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("View Source")
                                        .font(.highlighterBody)
                                        .fontWeight(.medium)
                                    
                                    Text(url)
                                        .font(.highlighterCaption)
                                        .foregroundColor(.highlighterSecondaryText)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.right")
                                    .foregroundColor(.highlighterSecondaryText)
                            }
                            .padding()
                            .background(Color.highlighterCardBackground)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: toggleZap) {
                            VStack(spacing: 4) {
                                Image(systemName: isZapped ? "bolt.fill" : "bolt")
                                    .font(.title2)
                                    .foregroundColor(isZapped ? .highlighterOrange : .highlighterSecondaryText)
                                
                                Text("Zap")
                                    .font(.highlighterCaption)
                                    .foregroundColor(isZapped ? .highlighterOrange : .highlighterSecondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.highlighterCardBackground)
                            .cornerRadius(12)
                        }
                        
                        Button(action: { showReplyComposer = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.title2)
                                    .foregroundColor(.highlighterSecondaryText)
                                
                                Text("Reply")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterSecondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.highlighterCardBackground)
                            .cornerRadius(12)
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                                    .foregroundColor(.highlighterSecondaryText)
                                
                                Text("Share")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterSecondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.highlighterCardBackground)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Related highlights section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Related Highlights")
                            .font(.highlighterHeadline)
                            .padding(.horizontal)
                        
                        // Placeholder for related highlights
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(0..<3) { _ in
                                    RelatedHighlightPlaceholder()
                                        .frame(width: 250)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }
                .padding(.vertical)
            }
            .background(Color.highlighterBackground)
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.highlighterPurple)
                }
            }
        }
        .task {
            await loadAuthorProfile()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [highlight.content])
        }
        .sheet(isPresented: $showReplyComposer) {
            ReplyComposerView(highlight: highlight, replyText: $replyText)
                .environmentObject(appState)
        }
    }
    
    private func loadAuthorProfile() async {
        guard let ndk = appState.ndk else { return }
        
        for await profile in await ndk.profileManager.observe(for: highlight.author, maxAge: 3600) {
            await MainActor.run {
                self.author = profile
            }
            break // Only need current value
        }
    }
    
    private func toggleZap() {
        isZapped.toggle()
        HapticType.light.trigger()
        // TODO: Implement actual zapping
    }
    
    private func followAuthor() {
        HapticType.light.trigger()
        // TODO: Implement follow functionality
    }
    
    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct RelatedHighlightPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 60)
                .shimmer()
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 20)
                .shimmer()
        }
        .padding()
        .cardStyle()
    }
}

struct ReplyComposerView: View {
    let highlight: HighlightEvent
    @Binding var replyText: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var isPublishing = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Quote preview
                Text("\"\(String(highlight.content.prefix(100)))...\"")
                    .font(.highlighterCaption)
                    .foregroundColor(.highlighterSecondaryText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.highlighterCardBackground)
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                // Reply input
                TextEditor(text: $replyText)
                    .font(.highlighterBody)
                    .padding(8)
                    .background(Color.highlighterCardBackground)
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        sendReply()
                    }
                    .disabled(replyText.isEmpty || isPublishing)
                }
            }
        }
    }
    
    private func sendReply() {
        isPublishing = true
        HapticType.light.trigger()
        // TODO: Implement reply functionality
        dismiss()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HighlightDetailView(
        highlight: HighlightEvent(
            id: "1",
            event: NDKEvent(id: "", pubkey: "", createdAt: 0, kind: 9802, tags: [], content: "", sig: ""),
            content: "The best way to predict the future is to invent it.",
            author: "test",
            createdAt: Date(),
            context: nil,
            url: "https://example.com",
            referencedEvent: nil,
            attributedAuthors: [],
            comment: "This is a profound insight about innovation."
        )
    )
    .environmentObject(AppState())
}