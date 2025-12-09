// FeedView.swift
import SwiftUI
import NDKSwift

public struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        _viewModel = StateObject(wrappedValue: FeedViewModel(ndk: ndk))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.posts, id: \.id) { event in
                        PostCard(event: event, ndk: ndk)
                            .padding(.bottom, 8)
                    }
                }
            }
            .refreshable {
                viewModel.stopSubscription()
                viewModel.startSubscription()
            }
            .navigationTitle("Olas")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Olas")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                }
            }
        }
        .onAppear {
            viewModel.startSubscription()
        }
        .onDisappear {
            viewModel.stopSubscription()
        }
        .overlay {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
            }

            if let error = viewModel.error {
                ContentUnavailableView(
                    "Unable to load feed",
                    systemImage: "wifi.slash",
                    description: Text(error.localizedDescription)
                )
            }

            if !viewModel.isLoading && viewModel.posts.isEmpty && viewModel.error == nil {
                ContentUnavailableView(
                    "No posts yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Follow some accounts or check back later")
                )
            }
        }
    }
}
