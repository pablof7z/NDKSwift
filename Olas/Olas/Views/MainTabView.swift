// MainTabView.swift
import SwiftUI
import NDKSwift

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var walletViewModel: WalletViewModel
    @State private var sparkWalletManager: SparkWalletManager
    @State private var muteListManager: MuteListManager
    @State private var blossomManager: NDKBlossomServerManager
    @State private var collectionsManager: CollectionsManager
    @State private var selectedTab = 0
    @State private var hasNotifications = false
    @State private var showCreatePost = false

    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        self._walletViewModel = State(wrappedValue: WalletViewModel(ndk: ndk))
        self._sparkWalletManager = State(wrappedValue: SparkWalletManager(ndk: ndk))
        self._muteListManager = State(wrappedValue: MuteListManager(ndk: ndk))
        self._blossomManager = State(wrappedValue: NDKBlossomServerManager(ndk: ndk))
        self._collectionsManager = State(wrappedValue: CollectionsManager(ndk: ndk))
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(ndk: ndk)
                .tabItem {
                    Label("Home", systemImage: selectedTab == 0 ? "wave.3.up.circle.fill" : "wave.3.up.circle")
                }
                .tag(0)
                .accessibilityIdentifier("homeTab")

            ExploreView(ndk: ndk)
                .tabItem {
                    Label("Explore", systemImage: selectedTab == 1 ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                }
                .tag(1)
                .accessibilityIdentifier("exploreTab")

            // Create - triggers sheet
            Color.clear
                .tabItem {
                    Label("", systemImage: "plus.app.fill")
                }
                .tag(2)
                .accessibilityIdentifier("createTab")

            // Wallet - Show Spark if connected, otherwise Cashu
            Group {
                if sparkWalletManager.connectionStatus == .connected {
                    SparkWalletView(walletManager: sparkWalletManager)
                } else {
                    WalletView(ndk: ndk, walletViewModel: walletViewModel, sparkWalletManager: sparkWalletManager)
                }
            }
            .tabItem {
                Label("Wallet", systemImage: selectedTab == 3 ? "creditcard.fill" : "creditcard")
            }
            .tag(3)
            .accessibilityIdentifier("walletTab")

            // Profile
            NavigationStack {
                if let pubkey = authViewModel.currentUser?.pubkey {
                    ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: pubkey, sparkWalletManager: sparkWalletManager)
                } else {
                    Text("Not logged in")
                }
            }
            .tabItem {
                Label("Profile", systemImage: selectedTab == 4 ? "person.fill" : "person")
            }
            .tag(4)
            .accessibilityIdentifier("profileTab")
        }
        .tint(.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 2 {
                showCreatePost = true
                selectedTab = oldValue
            }
        }
        .fullScreenCover(isPresented: $showCreatePost) {
            CreatePostView(ndk: ndk, blossomManager: blossomManager)
        }
        .task {
            await walletViewModel.loadWallet()
            await sparkWalletManager.restoreWalletIfExists()
            muteListManager.startSubscription()
            collectionsManager.startSubscription()
        }
        .environment(walletViewModel)
        .environment(muteListManager)
        .environment(collectionsManager)
    }
}
