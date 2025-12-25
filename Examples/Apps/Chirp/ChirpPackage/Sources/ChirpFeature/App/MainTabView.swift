import SwiftUI
import NDKSwiftCore

// MARK: - ChirpRootView

public struct ChirpRootView: View {
    @State private var state: ChirpState?
    @State private var initError: Error?

    public init() {}

    public var body: some View {
        Group {
            if let state = state {
                stateBasedContent(state)
            } else if let error = initError {
                errorView(error)
            } else {
                loadingView
            }
        }
        .task {
            await initializeState()
        }
    }

    @ViewBuilder
    private func stateBasedContent(_ state: ChirpState) -> some View {
        switch state.initState {
        case .loading:
            loadingView

        case .error(let error):
            errorView(error)

        case .needsLogin:
            WelcomeView()
                .environment(state)

        case .ready:
            MainTabView()
                .environment(state)
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "bird.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)

                ProgressView()
                    .tint(.white.opacity(0.6))

                Text("Initializing...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func errorView(_ error: Error) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Something went wrong")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Retry") {
                    Task { await initializeState() }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: 200)
                .frame(height: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func initializeState() async {
        initError = nil
        do {
            let newState = try await ChirpState.create()
            state = newState

            if newState.authManager.isAuthenticated {
                newState.initState = .ready
            } else {
                newState.initState = .needsLogin
            }
        } catch {
            initError = error
        }
    }
}

// MARK: - MainTabView

public struct MainTabView: View {
    @Environment(ChirpState.self) private var state
    @State private var selectedTab: Tab = .feed
    @State private var hasCheckedFollows = false

    enum Tab: Int {
        case feed = 0
        case explore = 1
        case wallet = 2
        case profile = 3
        case settings = 4
    }

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FeedView()
            }
            .tag(Tab.feed)
            .tabItem {
                Label("Feed", systemImage: "house.fill")
            }

            NavigationStack {
                ExploreView()
            }
            .tag(Tab.explore)
            .tabItem {
                Label("Explore", systemImage: "magnifyingglass")
            }

            NavigationStack {
                WalletView()
            }
            .tag(Tab.wallet)
            .tabItem {
                Label("Wallet", systemImage: "wallet.bifold.fill")
            }

            NavigationStack {
                ProfileView()
            }
            .tag(Tab.profile)
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tag(Tab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(.blue)
        .onAppear {
            // Default to Explore if user has no follows
            if !hasCheckedFollows {
                hasCheckedFollows = true
                if let followList = state.ndk.sessionData?.followList, followList.isEmpty {
                    selectedTab = .explore
                } else if state.ndk.sessionData?.followList == nil {
                    selectedTab = .explore
                }
            }
        }
    }
}
