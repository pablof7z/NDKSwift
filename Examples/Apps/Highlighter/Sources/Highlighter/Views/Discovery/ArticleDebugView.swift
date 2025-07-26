import SwiftUI
import NDKSwift

struct ArticleDebugView: View {
    @EnvironmentObject var appState: AppState
    @State private var debugInfo: String = "Loading articles..."
    @State private var articles: [Article] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Article Debug Info")
                    .font(.title)
                    .padding(.bottom)
                
                Text(debugInfo)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                if !articles.isEmpty {
                    ForEach(articles.prefix(5), id: \.id) { article in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title: \(article.title)")
                                .font(.headline)
                            Text("Author: \(article.author)")
                                .font(.caption)
                            Text("Content length: \(article.content.count) chars")
                                .font(.caption)
                            Text("First 100 chars: \(String(article.content.prefix(100)))")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Divider()
                        }
                        .padding()
                    }
                }
            }
            .padding()
        }
        .task {
            await loadAndDebugArticles()
        }
    }
    
    private func loadAndDebugArticles() async {
        guard let ndk = appState.ndk else { 
            debugInfo = "NDK not initialized"
            return 
        }
        
        debugInfo = "Fetching articles with kind 30023..."
        
        let articleSource = await ndk.outbox.observe(
            filter: NDKFilter(kinds: [30023], limit: 10),
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        var count = 0
        for await event in articleSource.events {
            count += 1
            debugInfo += "\n\nEvent #\(count):"
            debugInfo += "\n- ID: \(event.id)"
            debugInfo += "\n- Author: \(event.pubkey)"
            debugInfo += "\n- Content length: \(event.content.count)"
            debugInfo += "\n- Tags: \(event.tags.count)"
            
            // Check for title tag
            if let titleTag = event.tags.first(where: { $0.first == "title" }) {
                debugInfo += "\n- Title: \(titleTag[safe: 1] ?? "no title")"
            }
            
            do {
                let article = try Article(from: event)
                articles.append(article)
                debugInfo += "\n✅ Successfully created Article"
                debugInfo += "\n- Article title: \(article.title)"
                debugInfo += "\n- Article content: \(article.content.prefix(50))..."
            } catch {
                debugInfo += "\n❌ Failed to create Article: \(error)"
            }
            
            if count >= 5 { break }
        }
        
        if count == 0 {
            debugInfo += "\n\n⚠️ No events found with kind 30023"
        }
    }
}

// Helper extension
private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}