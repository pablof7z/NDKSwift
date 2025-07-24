import SwiftUI
import NDKSwift

/// Manages data streaming and state for the Home view
/// This class follows SRP by focusing solely on data management and streaming
@MainActor
class HomeDataManager: ObservableObject {
    // MARK: - Published State
    @Published var highlights: [HighlightEvent] = []
    @Published var highlightedArticles: [HighlightedArticle] = []
    @Published var discussions: [NDKEvent] = []
    @Published var zappedArticles: [NDKEvent] = []
    @Published var userHighlights: [HighlightEvent] = []
    @Published var isRefreshing = false
    
    // MARK: - Private Properties
    private var streamingTasks: [Task<Void, Never>] = []
    var appState: AppState? // Made non-weak and internal for setting from view
    
    // MARK: - Models
    struct HighlightedArticle {
        let article: Article
        let highlights: [HighlightEvent]
        let lastHighlightTime: Date
    }
    
    // MARK: - Initialization
    init(appState: AppState) {
        self.appState = appState
    }
    
    // MARK: - Public Methods
    
    /// Start streaming all data sources
    func startStreaming() async {
        guard let ndk = appState?.ndk else { return }
        
        stopAllStreams()
        
        // Start all streams concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.streamHighlights(ndk: ndk) }
            group.addTask { await self.streamUserHighlights(ndk: ndk) }
            group.addTask { await self.streamDiscussions(ndk: ndk) }
            group.addTask { await self.streamZappedArticles(ndk: ndk) }
        }
    }
    
    /// Refresh all content by clearing and re-streaming
    func refresh() async {
        isRefreshing = true
        HapticManager.shared.impact(.light)
        
        // Clear all data
        highlights.removeAll()
        highlightedArticles.removeAll()
        discussions.removeAll()
        zappedArticles.removeAll()
        userHighlights.removeAll()
        
        // Restart streaming
        await startStreaming()
        
        HapticManager.shared.notification(.success)
        isRefreshing = false
    }
    
    /// Stop all streaming tasks
    func stopAllStreams() {
        for task in streamingTasks {
            task.cancel()
        }
        streamingTasks.removeAll()
    }
    
    // MARK: - Private Streaming Methods
    
    private func streamHighlights(ndk: NDK) async {
        let task = Task {
            let highlightSource = ndk.observe(
                filter: NDKFilter(kinds: [9802], limit: 50),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            var articleReferences: Set<String> = []
            var highlightsByArticle: [String: [HighlightEvent]] = [:]
            
            for await event in highlightSource.events {
                if let highlight = try? HighlightEvent(from: event) {
                    await MainActor.run {
                        withAnimation(DesignSystem.Animation.quick) {
                            if !highlights.contains(where: { $0.id == highlight.id }) {
                                highlights.append(highlight)
                                highlights.sort { $0.createdAt > $1.createdAt }
                                
                                // Track article references for highlighted articles
                                if let ref = highlight.referencedEvent {
                                    articleReferences.insert(ref)
                                    if highlightsByArticle[ref] != nil {
                                        highlightsByArticle[ref]?.append(highlight)
                                    } else {
                                        highlightsByArticle[ref] = [highlight]
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Fetch referenced articles if any
            if !articleReferences.isEmpty {
                await fetchHighlightedArticles(
                    ndk: ndk,
                    references: Array(articleReferences),
                    highlightsByArticle: highlightsByArticle
                )
            }
        }
        streamingTasks.append(task)
    }
    
    private func streamUserHighlights(ndk: NDK) async {
        guard let signer = appState?.activeSigner else { return }
        
        let task = Task {
            do {
                let userPubkey = try await signer.pubkey
                let userHighlightSource = ndk.observe(
                    filter: NDKFilter(
                        authors: [userPubkey],
                        kinds: [9802],
                        limit: 5
                    ),
                    maxAge: 3600
                )
                
                for await event in userHighlightSource.events {
                    if let highlight = try? HighlightEvent(from: event) {
                        await MainActor.run {
                            withAnimation(DesignSystem.Animation.quick) {
                                if !userHighlights.contains(where: { $0.id == highlight.id }) {
                                    userHighlights.append(highlight)
                                    userHighlights.sort { $0.createdAt > $1.createdAt }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Failed to get user pubkey: \(error)")
            }
        }
        streamingTasks.append(task)
    }
    
    private func streamDiscussions(ndk: NDK) async {
        let task = Task {
            let discussionSource = ndk.observe(
                filter: NDKFilter(kinds: [1], limit: 10, tags: ["t": Set(["bookstr"])]),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in discussionSource.events {
                await MainActor.run {
                    withAnimation(DesignSystem.Animation.quick) {
                        if !discussions.contains(where: { $0.id == event.id }) {
                            discussions.append(event)
                            discussions.sort { $0.createdAt > $1.createdAt }
                        }
                    }
                }
            }
        }
        streamingTasks.append(task)
    }
    
    private func streamZappedArticles(ndk: NDK) async {
        let task = Task {
            let zapSource = ndk.observe(
                filter: NDKFilter(kinds: [9735], limit: 10),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in zapSource.events {
                await MainActor.run {
                    withAnimation(DesignSystem.Animation.quick) {
                        if !zappedArticles.contains(where: { $0.id == event.id }) {
                            zappedArticles.append(event)
                        }
                    }
                }
            }
        }
        streamingTasks.append(task)
    }
    
    private func fetchHighlightedArticles(
        ndk: NDK,
        references: [String],
        highlightsByArticle: [String: [HighlightEvent]]
    ) async {
        // Parse references to extract article IDs
        var articleFilters: [NDKFilter] = []
        
        for reference in references {
            if reference.contains(":") {
                // This is an "a" tag reference (kind:pubkey:d-tag)
                let parts = reference.split(separator: ":")
                if parts.count >= 3,
                   let kind = Int(parts[0]) {
                    articleFilters.append(NDKFilter(
                        authors: [String(parts[1])],
                        kinds: [kind],
                        tags: ["d": Set([String(parts[2])])]
                    ))
                }
            } else {
                // This is an "e" tag reference (event ID)
                articleFilters.append(NDKFilter(ids: [reference]))
            }
        }
        
        // Stream articles
        for filter in articleFilters {
            let task = Task {
                let dataSource = ndk.observe(
                    filter: filter,
                    maxAge: 300,
                    cachePolicy: .cacheWithNetwork
                )
                
                for await event in dataSource.events {
                    if event.kind == 30023,
                       let article = try? Article(from: event),
                       let highlights = highlightsByArticle[event.id] ?? highlightsByArticle["\(event.kind):\(event.pubkey):\(article.identifier ?? "")"] {
                        
                        let lastHighlight = highlights.max(by: { $0.createdAt < $1.createdAt })
                        
                        await MainActor.run {
                            withAnimation(DesignSystem.Animation.quick) {
                                let highlightedArticle = HighlightedArticle(
                                    article: article,
                                    highlights: highlights,
                                    lastHighlightTime: lastHighlight?.createdAt ?? Date()
                                )
                                
                                if !highlightedArticles.contains(where: { $0.article.id == article.id }) {
                                    highlightedArticles.append(highlightedArticle)
                                    highlightedArticles.sort { $0.lastHighlightTime > $1.lastHighlightTime }
                                }
                            }
                        }
                    }
                }
            }
            streamingTasks.append(task)
        }
    }
    
    // MARK: - Cleanup
    deinit {
        stopAllStreams()
    }
}