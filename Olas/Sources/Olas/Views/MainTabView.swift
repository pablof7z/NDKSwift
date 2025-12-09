// MainTabView.swift
import SwiftUI
import NDKSwift

public struct MainTabView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var walletViewModel: WalletViewModel
    @StateObject private var muteListManager: MuteListManager
    @State private var selectedTab = 0
    @State private var showCreatePost = false

    private let ndk: NDK
    @ObservedObject private var sparkWalletManager: SparkWalletManager

    public init(ndk: NDK, sparkWalletManager: SparkWalletManager) {
        self.ndk = ndk
        self._walletViewModel = StateObject(wrappedValue: WalletViewModel(ndk: ndk))
        self._muteListManager = StateObject(wrappedValue: MuteListManager(ndk: ndk))
        self.sparkWalletManager = sparkWalletManager
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(ndk: ndk)
                .tabItem {
                    Label("Home", systemImage: selectedTab == 0 ? "wave.3.up.circle.fill" : "wave.3.up.circle")
                }
                .tag(0)

            ExploreView(ndk: ndk)
                .tabItem {
                    Label("Explore", systemImage: selectedTab == 1 ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                }
                .tag(1)

            // Create - triggers sheet
            Color.clear
                .tabItem {
                    Label("", systemImage: "plus.app.fill")
                }
                .tag(2)

            // Wallet (cashu/NIP-60)
            WalletView(ndk: ndk, walletViewModel: walletViewModel)
                .tabItem {
                    Label("Wallet", systemImage: selectedTab == 3 ? "creditcard.fill" : "creditcard")
                }
                .tag(3)

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
        }
        .tint(.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 2 {
                showCreatePost = true
                selectedTab = oldValue
            }
        }
        .fullScreenCover(isPresented: $showCreatePost) {
            CreatePostView(ndk: ndk)
        }
        .task {
            await walletViewModel.loadWallet()
            muteListManager.startSubscription()
        }
        .environmentObject(walletViewModel)
        .environmentObject(muteListManager)
        .environmentObject(sparkWalletManager)
    }
}
