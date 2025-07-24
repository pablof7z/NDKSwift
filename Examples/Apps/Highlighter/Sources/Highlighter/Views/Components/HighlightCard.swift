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
                Text("\"\(highlight.content)\"")
                    .font(.highlighterQuote)
                    .foregroundColor(.highlighterText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Comment if available
                if let comment = highlight.comment {
                    Text(comment)
                        .font(.highlighterBody)
                        .foregroundColor(.highlighterSecondaryText)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
                
                // Metadata row
                HStack {
                    // Author
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.highlighterPurple)
                        
                        Text(author?.name ?? author?.displayName ?? String(highlight.author.prefix(8)))
                            .font(.highlighterCaption)
                            .fontWeight(.medium)
                            .foregroundColor(.highlighterText)
                    }
                    
                    Spacer()
                    
                    // Actions
                    HStack(spacing: 16) {
                        // Zap button
                        Button(action: zapHighlight) {
                            Image(systemName: isZapped ? "bolt.fill" : "bolt")
                                .font(.system(size: 16))
                                .foregroundColor(isZapped ? .highlighterOrange : .highlighterSecondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Time
                        Text(relativeTime(from: highlight.createdAt))
                            .font(.highlighterCaption)
                            .foregroundColor(.highlighterSecondaryText)
                    }
                }
                
                // Source indicator
                if let url = highlight.url {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text(URL(string: url)?.host ?? "Source")
                            .font(.highlighterCaption)
                    }
                    .foregroundColor(.highlighterPurple)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.highlighterCardBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.highlighterPurple.opacity(isZapped ? 0.3 : 0.1),
                                Color.highlighterOrange.opacity(isZapped ? 0.3 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
        HapticType.light.trigger()
        // TODO: Implement actual zapping
    }
    
    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Compact version for horizontal scrolls
struct CompactHighlightCard: View {
    let highlight: HighlightEvent
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\"\(highlight.content)\"")
                    .font(.highlighterBody)
                    .fontWeight(.medium)
                    .foregroundColor(.highlighterText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(minHeight: 60, alignment: .topLeading)
                
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.highlighterPurple)
                    
                    Text(String(highlight.author.prefix(8)))
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                    
                    Spacer()
                    
                    Image(systemName: "bolt")
                        .font(.system(size: 14))
                        .foregroundColor(.highlighterSecondaryText)
                }
            }
            .padding()
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.highlighterCardBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
        
        ScrollView(.horizontal) {
            HStack {
                CompactHighlightCard(
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
    .background(Color.highlighterBackground)
}