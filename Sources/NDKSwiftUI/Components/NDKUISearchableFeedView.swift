import SwiftUI
import NDKSwiftCore

// MARK: - NDKUISearchableFeedView

/// Feed view with bottom search bar (when nostrdb is available)
///
/// Features:
/// - Displays event feed using NDKSubscription
/// - Bottom search bar (iOS 18+ style) when nostrdb cache is active
/// - Real-time search on every keystroke
/// - Search results replace feed content
/// - Empty state for no results
///
/// ## Usage
///
/// ```swift
/// NDKUISearchableFeedView(
///     ndk: ndk,
///     filter: NDKFilter(kinds: [1], limit: 20)
/// )
/// ```
public struct NDKUISearchableFeedView: View {
    private let ndk: NDK
    @State private var feedDataSource: NDKSubscription<NDKEvent>
    @State private var searchDataSource: NDKSearchDataSource
    @State private var searchText: String = ""

    public init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0
    ) {
        self.ndk = ndk
        self._feedDataSource = State(initialValue: NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: .cacheWithNetwork
        ))
        self._searchDataSource = State(initialValue: NDKSearchDataSource(ndk: ndk, limit: 100))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main content area
            if searchText.isEmpty {
                // Show feed when not searching
                feedContent
            } else {
                // Show search results when searching
                searchResultsContent
            }

            // Bottom search bar (always visible for debugging)
            VStack(spacing: 0) {
                // Debug info
                if !searchDataSource.isNostrDBAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("NostrDB cache not detected - search will not work")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchDataSource.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchDataSource.search(query: newValue)
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        Group {
            if feedDataSource.data.isEmpty {
                emptyFeedView
            } else {
                eventList(events: feedDataSource.data)
            }
        }
    }

    // MARK: - Search Results Content

    private var searchResultsContent: some View {
        Group {
            if searchDataSource.isLoading {
                loadingView
            } else if let error = searchDataSource.error {
                errorView(error)
            } else if searchDataSource.events.isEmpty {
                emptySearchView
            } else {
                eventList(events: searchDataSource.events)
            }
        }
    }

    // MARK: - Event List

    private func eventList(events: [NDKEvent]) -> some View {
        List {
            ForEach(events, id: \.id) { event in
                NDKUIEventView(ndk: ndk, event: event)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Error")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - Empty States

    private var emptyFeedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No events")
                .font(.headline)
            Text("No events found matching the filter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No results found")
                .font(.headline)
            Text("Try a different search query")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    // Preview with mock NDK
    let ndk = NDK()
    let filter = NDKFilter(kinds: [1], limit: 20)

    return NDKUISearchableFeedView(ndk: ndk, filter: filter)
}
