import SwiftUI
import NDKSwift

struct SimplifiedHybridFeedView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dataManager = HomeDataManager()
    @State private var selectedSection = 0
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    headerView
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    
                    // Featured Highlights Carousel
                    if !dataManager.userHighlights.isEmpty {
                        carouselSection(
                            title: "Featured Highlights",
                            items: dataManager.userHighlights
                        ) { highlight in
                            HighlightCarouselCard(highlight: highlight)
                        }
                    }
                    
                    // Active Discussions
                    if !dataManager.discussions.isEmpty {
                        discussionsSection
                    }
                    
                    // Trending Content Carousel
                    if !dataManager.zappedArticles.isEmpty {
                        carouselSection(
                            title: "Trending",
                            items: dataManager.zappedArticles
                        ) { event in
                            TrendingCard(event: event)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .background(Color.ds.background)
            .navigationBarHidden(true)
        }
        .onAppear {
            dataManager.appState = appState
        }
        .task {
            await dataManager.startStreaming()
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GreetingFormatter.timeBasedGreeting())
                .font(.ds.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.ds.text)
            
            Text(GreetingFormatter.formattedDate())
                .font(.ds.footnote)
                .foregroundColor(.ds.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func carouselSection<Item: Identifiable, Content: View>(
        title: String,
        items: [Item],
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.ds.title3)
                .fontWeight(.semibold)
                .foregroundColor(.ds.text)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        content(item)
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var discussionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Discussions")
                .font(.ds.title3)
                .fontWeight(.semibold)
                .foregroundColor(.ds.text)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(dataManager.discussions.prefix(3), id: \.id) { event in
                    DiscussionRow(event: event)
                    
                    if event.id != dataManager.discussions.prefix(3).last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color.ds.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Carousel Cards

struct HighlightCarouselCard: View {
    let highlight: HighlightEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\"\(highlight.content)\"")
                .font(.ds.headline)
                .foregroundColor(.ds.text)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            HStack {
                Text(RelativeTimeFormatter.relativeTime(from: highlight.createdAt ?? Date()))
                    .font(.ds.caption)
                    .foregroundColor(.ds.textTertiary)
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(.ds.primary)
            }
        }
        .padding(20)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.ds.surfaceSecondary)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct TrendingCard: View {
    let event: NDKEvent
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.title)
                .foregroundColor(.yellow)
                .frame(width: 50, height: 50)
                .background(Color.yellow.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Zapped Content")
                    .font(.ds.headline)
                    .foregroundColor(.ds.text)
                
                Text(event.content.prefix(60) + "...")
                    .font(.ds.caption)
                    .foregroundColor(.ds.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.ds.surfaceSecondary)
        )
    }
}

#Preview {
    SimplifiedHybridFeedView()
        .environmentObject(AppState())
}