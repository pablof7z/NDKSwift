import SwiftUI
import NDKSwift

struct ArticleListView: View {
    @EnvironmentObject var appState: AppState
    @State private var articles: [Article] = []
    @State private var selectedArticle: Article?
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .spacingL) {
                    if articles.isEmpty && !isLoading {
                        emptyState
                    } else {
                        LazyVStack(spacing: .spacingM) {
                            ForEach(articles) { article in
                                ArticleListCard(article: article)
                                    .onTapGesture {
                                        selectedArticle = article
                                        HapticType.light.trigger()
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Articles")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadArticles()
            }
            .sheet(item: $selectedArticle) { article in
                ArticleView(article: article)
            }
            .overlay {
                if isLoading && articles.isEmpty {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
        .task {
            await loadArticles()
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: .spacingL) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.highlighterSecondaryText)
            
            Text("No articles yet")
                .font(.highlighterHeadline)
                .foregroundColor(.highlighterText)
            
            Text("Long-form articles will appear here")
                .font(.highlighterBody)
                .foregroundColor(.highlighterSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.spacingXL)
    }
    
    private func loadArticles() async {
        guard let ndk = appState.ndk else { return }
        
        isLoading = true
        
        let articleSource = ndk.observe(
            filter: NDKFilter(kinds: [30023], limit: 50),
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in articleSource.events {
            if let article = try? Article(from: event) {
                await MainActor.run {
                    if !articles.contains(where: { $0.id == article.id }) {
                        articles.append(article)
                        articles.sort { $0.createdAt > $1.createdAt }
                    }
                }
            }
        }
        
        isLoading = false
    }
}

// MARK: - Article Card

struct ArticleListCard: View {
    let article: Article
    @State private var author: NDKUserProfile?
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingM) {
            // Image
            if let imageURL = article.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .clipped()
                    case .failure(_), .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 180)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: .spacingS) {
                // Title
                Text(article.title)
                    .font(.highlighterHeadline)
                    .foregroundColor(.highlighterText)
                    .lineLimit(2)
                
                // Summary
                if let summary = article.summary {
                    Text(summary)
                        .font(.highlighterBody)
                        .foregroundColor(.highlighterSecondaryText)
                        .lineLimit(3)
                }
                
                // Metadata
                HStack {
                    // Author
                    HStack(spacing: .spacingXS) {
                        Circle()
                            .fill(Color.highlighterPurple.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if let picture = author?.picture, let url = URL(string: picture) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .clipShape(Circle())
                                    } placeholder: {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.highlighterPurple)
                                    }
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.highlighterPurple)
                                }
                            }
                        
                        Text(author?.displayName ?? formatPubkey(article.author))
                            .font(.highlighterCaption)
                            .foregroundColor(.highlighterSecondaryText)
                    }
                    
                    Spacer()
                    
                    // Reading time
                    Label("\(article.estimatedReadingTime) min", systemImage: "clock")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                    
                    // Date
                    if let publishedAt = article.publishedAt {
                        Text("•")
                            .foregroundColor(.highlighterSecondaryText)
                        Text(publishedAt.formatted(.relative(presentation: .named)))
                            .font(.highlighterCaption)
                            .foregroundColor(.highlighterSecondaryText)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
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
}

#Preview {
    ArticleListView()
        .environmentObject(AppState())
}