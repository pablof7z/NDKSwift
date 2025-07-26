import Foundation
import NDKSwift
import Combine

@MainActor
class BookmarkService: ObservableObject {
    @Published private(set) var bookmarkedArticles: [String: Article] = [:]
    @Published private(set) var bookmarkedHighlights: [String: HighlightEvent] = [:]
    @Published private(set) var isLoading = false
    
    private var ndk: NDK?
    private var signer: NDKSigner?
    private var currentUserPubkey: String?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    
    func configure(with ndk: NDK, signer: NDKSigner?) {
        self.ndk = ndk
        self.signer = signer
        
        Task {
            if let signer = signer {
                currentUserPubkey = try? await signer.publicKey(format: .hex)
                await loadBookmarks()
            }
        }
    }
    
    // MARK: - Article Bookmarks
    
    func isArticleBookmarked(_ articleId: String) -> Bool {
        bookmarkedArticles[articleId] != nil
    }
    
    func toggleArticleBookmark(_ article: Article) async throws {
        guard let ndk = ndk, let signer = signer else {
            throw BookmarkError.notConfigured
        }
        
        if isArticleBookmarked(article.id) {
            // Remove bookmark
            await removeArticleBookmark(article.id)
            
            // Publish deletion event (NIP-09)
            if let existingEventId = findBookmarkEventId(for: article.id) {
                try await publishDeletionEvent(for: existingEventId)
            }
        } else {
            // Add bookmark
            await addArticleBookmark(article)
            
            // Publish bookmark event (kind 30001)
            try await publishArticleBookmark(article)
        }
    }
    
    private func addArticleBookmark(_ article: Article) async {
        await MainActor.run {
            bookmarkedArticles[article.id] = article
        }
        saveToLocalStorage()
    }
    
    private func removeArticleBookmark(_ articleId: String) async {
        await MainActor.run {
            bookmarkedArticles.removeValue(forKey: articleId)
        }
        saveToLocalStorage()
    }
    
    // MARK: - Highlight Bookmarks
    
    func isHighlightBookmarked(_ highlightId: String) -> Bool {
        bookmarkedHighlights[highlightId] != nil
    }
    
    func toggleHighlightBookmark(_ highlight: HighlightEvent) async throws {
        guard let ndk = ndk, let signer = signer else {
            throw BookmarkError.notConfigured
        }
        
        if isHighlightBookmarked(highlight.id) {
            await removeHighlightBookmark(highlight.id)
            
            if let existingEventId = findHighlightBookmarkEventId(for: highlight.id) {
                try await publishDeletionEvent(for: existingEventId)
            }
        } else {
            await addHighlightBookmark(highlight)
            try await publishHighlightBookmark(highlight)
        }
    }
    
    private func addHighlightBookmark(_ highlight: HighlightEvent) async {
        await MainActor.run {
            bookmarkedHighlights[highlight.id] = highlight
        }
        saveToLocalStorage()
    }
    
    private func removeHighlightBookmark(_ highlightId: String) async {
        await MainActor.run {
            bookmarkedHighlights.removeValue(forKey: highlightId)
        }
        saveToLocalStorage()
    }
    
    // MARK: - Nostr Publishing
    
    private func publishArticleBookmark(_ article: Article) async throws {
        guard let ndk = ndk, let signer = signer else { return }
        
        // Create bookmark list event (NIP-51, kind 30001)
        let tags: [[String]] = [
            ["d", "articles"], // Replaceable event identifier
            ["name", "Bookmarked Articles"],
            ["a", "\(article.identifier)::\(article.author)", "wss://relay.damus.io", article.title]
        ]
        
        let content = JSONCoding.encode([
            "bookmarked_at": ISO8601DateFormatter().string(from: Date()),
            "note": "Saved for later reading"
        ])
        
        let event = NDKEvent(
            kind: 30001, // Bookmark list
            content: content,
            tags: tags
        )
        
        try await event.sign(with: signer)
        try await ndk.publish(event)
    }
    
    private func publishHighlightBookmark(_ highlight: HighlightEvent) async throws {
        guard let ndk = ndk, let signer = signer else { return }
        
        let tags: [[String]] = [
            ["d", "highlights"],
            ["name", "Bookmarked Highlights"],
            ["e", highlight.id, "wss://relay.damus.io", "highlight"]
        ]
        
        let content = JSONCoding.encode([
            "bookmarked_at": ISO8601DateFormatter().string(from: Date()),
            "highlight_content": highlight.content
        ])
        
        let event = NDKEvent(
            kind: 30001,
            content: content,
            tags: tags
        )
        
        try await event.sign(with: signer)
        try await ndk.publish(event)
    }
    
    private func publishDeletionEvent(for eventId: String) async throws {
        guard let ndk = ndk, let signer = signer else { return }
        
        let event = NDKEvent(
            kind: 5, // Deletion
            content: "Removed bookmark",
            tags: [["e", eventId]]
        )
        
        try await event.sign(with: signer)
        try await ndk.publish(event)
    }
    
    // MARK: - Loading
    
    private func loadBookmarks() async {
        guard let ndk = ndk, let currentUserPubkey = currentUserPubkey else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Load from local storage first
        loadFromLocalStorage()
        
        // Then sync with Nostr
        let filter = NDKFilter(
            authors: [currentUserPubkey],
            kinds: [30001],
            tags: ["d": ["articles", "highlights"]]
        )
        
        do {
            let events = try await ndk.fetchEvents(filter)
            await processBookmarkEvents(events)
        } catch {
            print("Failed to load bookmarks: \(error)")
        }
    }
    
    private func processBookmarkEvents(_ events: [NDKEvent]) async {
        for event in events {
            guard let dTag = event.tags.first(where: { $0.first == "d" })?.dropFirst().first else {
                continue
            }
            
            switch dTag {
            case "articles":
                await processArticleBookmarks(from: event)
            case "highlights":
                await processHighlightBookmarks(from: event)
            default:
                break
            }
        }
    }
    
    private func processArticleBookmarks(from event: NDKEvent) async {
        let articleTags = event.tags.filter { $0.first == "a" }
        
        for tag in articleTags {
            guard tag.count >= 4,
                  let articleData = tag[1].split(separator: ":").map(String.init),
                  articleData.count >= 2 else {
                continue
            }
            
            let articleId = articleData[0]
            let author = articleData[1]
            let title = tag[3]
            
            // Create article from bookmark data
            let article = Article(
                id: articleId,
                identifier: articleId,
                title: title,
                summary: nil,
                content: "", // Will be loaded when opened
                author: author,
                publishedAt: Date(),
                image: nil,
                hashtags: [],
                createdAt: event.createdAt
            )
            
            await addArticleBookmark(article)
        }
    }
    
    private func processHighlightBookmarks(from event: NDKEvent) async {
        // Process highlight bookmarks from event tags
        let highlightTags = event.tags.filter { $0.first == "e" }
        
        for tag in highlightTags where tag.count >= 2 {
            let highlightId = tag[1]
            
            // Fetch the actual highlight event
            if let ndk = ndk {
                let filter = NDKFilter(ids: [highlightId])
                
                do {
                    if let highlightEvent = try await ndk.fetchEvent(filter) {
                        // Convert to HighlightEvent
                        let highlight = HighlightEvent(
                            content: highlightEvent.content,
                            articleId: "", // Extract from tags if available
                            author: highlightEvent.pubkey,
                            createdAt: highlightEvent.createdAt
                        )
                        
                        await addHighlightBookmark(highlight)
                    }
                } catch {
                    print("Failed to fetch highlight: \(error)")
                }
            }
        }
    }
    
    // MARK: - Local Storage
    
    private func saveToLocalStorage() {
        let bookmarkData = BookmarkData(
            articles: Array(bookmarkedArticles.values),
            highlights: Array(bookmarkedHighlights.values)
        )
        
        if let encoded = try? JSONEncoder().encode(bookmarkData) {
            UserDefaults.standard.set(encoded, forKey: "highlighter.bookmarks")
        }
    }
    
    private func loadFromLocalStorage() {
        guard let data = UserDefaults.standard.data(forKey: "highlighter.bookmarks"),
              let bookmarkData = try? JSONDecoder().decode(BookmarkData.self, from: data) else {
            return
        }
        
        bookmarkedArticles = Dictionary(uniqueKeysWithValues: bookmarkData.articles.map { ($0.id, $0) })
        bookmarkedHighlights = Dictionary(uniqueKeysWithValues: bookmarkData.highlights.map { ($0.id, $0) })
    }
    
    // MARK: - Helpers
    
    private func findBookmarkEventId(for articleId: String) -> String? {
        // This would need to track event IDs when loading bookmarks
        // For now, return nil
        return nil
    }
    
    private func findHighlightBookmarkEventId(for highlightId: String) -> String? {
        return nil
    }
}

// MARK: - Supporting Types

private struct BookmarkData: Codable {
    let articles: [Article]
    let highlights: [HighlightEvent]
}

enum BookmarkError: LocalizedError {
    case notConfigured
    case publishFailed
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Bookmark service not configured"
        case .publishFailed:
            return "Failed to publish bookmark"
        }
    }
}