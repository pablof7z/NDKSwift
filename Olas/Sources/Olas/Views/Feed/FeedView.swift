// FeedView.swift
import SwiftUI
import NDKSwift

public struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    @StateObject private var relayMetadataCache = RelayMetadataCache.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var muteListManager: MuteListManager
    private let ndk: NDK

    @State private var navigationPath = NavigationPath()

    public init(ndk: NDK) {
        self.ndk = ndk
        _viewModel = StateObject(wrappedValue: FeedViewModel(ndk: ndk))
    }

    private var currentFeedDisplayName: String {
        switch viewModel.feedMode {
        case .following:
            return "Following"
        case .relay(let url):
            return relayMetadataCache.displayName(for: url)
        }
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.posts, id: \.id) { event in
                        PostCard(event: event, ndk: ndk) { pubkey in
                            navigationPath.append(pubkey)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .refreshable {
                viewModel.stopSubscription()
                viewModel.startSubscription(muteListManager: muteListManager)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            viewModel.switchMode(to: .following, muteListManager: muteListManager)
                        } label: {
                            Label("Following", systemImage: viewModel.feedMode == .following ? "checkmark" : "")
                        }

                        Divider()

                        ForEach(DiscoveryRelays.relays, id: \.self) { relayURL in
                            Button {
                                viewModel.switchMode(to: .relay(url: relayURL), muteListManager: muteListManager)
                            } label: {
                                let isSelected = viewModel.feedMode == .relay(url: relayURL)
                                Label(relayMetadataCache.displayName(for: relayURL), systemImage: isSelected ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentFeedDisplayName)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationDestination(for: String.self) { pubkey in
                ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: authViewModel.currentUser?.pubkey)
            }
        }
        .onAppear {
            viewModel.startSubscription(muteListManager: muteListManager)
            Task {
                for relayURL in DiscoveryRelays.relays {
                    await relayMetadataCache.fetchMetadata(for: relayURL)
                }
            }
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
