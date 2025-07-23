import SwiftUI
import NDKSwift

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = FeedViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.items) { item in
                        FeedItemView(item: item)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Olas")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.refresh()
            }
            .onAppear {
                if let ndk = appState.ndk {
                    viewModel.startFeed(with: ndk)
                }
            }
        }
    }
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var items: [FeedItem] = []
    private var subscription: NDKSubscription?
    
    func startFeed(with ndk: NDK) {
        Task {
            let filter = NDKFilter(kinds: [20]) // Picture events
            
            for await event in ndk.subscribe(filter) {
                let feedItem = FeedItem(from: event)
                items.insert(feedItem, at: 0)
                
                // Fetch profile asynchronously
                Task {
                    if let profile = try? await ndk.fetchProfile(event.pubkey) {
                        updateItem(event.id, with: profile)
                    }
                }
            }
        }
    }
    
    func refresh() async {
        // Implement refresh logic
    }
    
    private func updateItem(_ eventId: String, with profile: NDKUserProfile) {
        if let index = items.firstIndex(where: { $0.id == eventId }) {
            items[index].profile = profile
        }
    }
}

struct FeedItem: Identifiable {
    let id: String
    let event: NDKEvent
    var profile: NDKUserProfile?
    
    init(from event: NDKEvent) {
        self.id = event.id
        self.event = event
    }
}