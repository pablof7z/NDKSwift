import SwiftUI
import NDKSwift

struct HighlightCard: View {
    let highlight: HighlightEvent
    @EnvironmentObject var appState: AppState
    @State private var author: NDKUserProfile?
    @State private var isZapped = false
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
                // Quote
                Text(ContentFormatter.formatHighlight(highlight.content))
                    .font(.ds.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.ds.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Comment if available
                if let comment = highlight.comment {
                    Text(comment)
                        .font(.ds.body)
                        .foregroundColor(.ds.textSecondary)
                        .lineLimit(2)
                        .padding(.top, .ds.micro)
                }
                
                // Metadata row
                HStack {
                    // Author
                    HStack(spacing: .ds.small) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.ds.primary)
                        
                        Text(PubkeyFormatter.displayName(from: author, pubkey: highlight.author))
                            .font(.ds.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.ds.text)
                    }
                    
                    Spacer()
                    
                    // Actions
                    HStack(spacing: .ds.medium) {
                        // Zap button
                        Button(action: zapHighlight) {
                            Image(systemName: isZapped ? "bolt.fill" : "bolt")
                                .font(.system(size: 16))
                                .foregroundColor(isZapped ? .ds.warning : .ds.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Time
                        Text(RelativeTimeFormatter.relativeTime(from: highlight.createdAt))
                            .font(.ds.caption)
                            .foregroundColor(.ds.textSecondary)
                    }
                }
                
                // Source indicator
                if let url = highlight.url {
                    HStack(spacing: .ds.micro) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text(ContentFormatter.extractDomain(from: url))
                            .font(.ds.caption)
                    }
                    .foregroundColor(.ds.primary)
                }
            }
            .padding(.ds.cardPadding)
        }
        .buttonStyle(PlainButtonStyle())
        .modernCardSelected(isSelected: isZapped)
        .task {
            await loadAuthor()
        }
        .sheet(isPresented: $showDetail) {
            HighlightDetailView(highlight: highlight)
                .environmentObject(appState)
        }
    }
    
    private func loadAuthor() async {
        guard let ndk = appState.ndk else { return }
        
        for await profile in await ndk.profileManager.observe(for: highlight.author, maxAge: 3600) {
            await MainActor.run {
                self.author = profile
            }
            break
        }
    }
    
    private func zapHighlight() {
        isZapped.toggle()
        HapticManager.shared.impact(HapticManager.ImpactStyle.light)
        // TODO: Implement actual zapping
    }
    
}

// Compact version for horizontal scrolls
struct CompactHighlightCardView: View {
    let highlight: HighlightEvent
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: .ds.small) {
                Text(ContentFormatter.formatHighlight(highlight.content))
                    .font(.ds.body)
                    .fontWeight(.medium)
                    .foregroundColor(.ds.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(minHeight: 60, alignment: .topLeading)
                
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.ds.primary)
                    
                    Text(PubkeyFormatter.formatShort(highlight.author))
                        .font(.ds.caption)
                        .foregroundColor(.ds.textSecondary)
                    
                    Spacer()
                    
                    Image(systemName: "bolt")
                        .font(.system(size: 14))
                        .foregroundColor(.ds.textSecondary)
                }
            }
            .padding(.ds.base)
            .frame(width: 280)
        }
        .buttonStyle(PlainButtonStyle())
        .modernCard()
        .sheet(isPresented: $showDetail) {
            HighlightDetailView(highlight: highlight)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HighlightCard(
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
                comment: "A profound insight"
            )
        )
        .environmentObject(AppState())
        .padding()
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                CompactHighlightCardView(
                    highlight: HighlightEvent(
                        id: "2",
                        event: NDKEvent(id: "", pubkey: "", createdAt: 0, kind: 9802, tags: [], content: "", sig: ""),
                        content: "Innovation distinguishes between a leader and a follower.",
                        author: "test2",
                        createdAt: Date(),
                        context: nil,
                        url: nil,
                        referencedEvent: nil,
                        attributedAuthors: [],
                        comment: nil
                    )
                )
            }
            .padding(.horizontal)
        }
    }
    .background(DesignSystem.Colors.background)
}
