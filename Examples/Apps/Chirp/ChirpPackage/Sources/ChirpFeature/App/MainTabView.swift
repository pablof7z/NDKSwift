import SwiftUI
import NDKSwiftCore

// MARK: - ChirpRootView

public struct ChirpRootView: View {
    @State private var state: ChirpState?
    @State private var initError: Error?
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: CGFloat = 0
    @State private var splashBackgroundOpacity: CGFloat = 1.0

    public init() {}

    public var body: some View {
        ZStack {
            // Content layer (always rendered behind splash)
            contentView

            // Splash overlay - uses opacity instead of conditional removal
            splashView
                .opacity(splashBackgroundOpacity)
                .allowsHitTesting(splashBackgroundOpacity > 0)
        }
        .task {
            await initializeState()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let state = state {
            switch state.initState {
            case .loading:
                Color(.systemBackground).ignoresSafeArea()
            case .error(let error):
                errorView(error)
            case .needsLogin:
                WelcomeView()
                    .environment(state)
            case .ready:
                MainTabView()
                    .environment(state)
            }
        } else if let error = initError {
            errorView(error)
        } else {
            Color(.systemBackground).ignoresSafeArea()
        }
    }

    private var splashView: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                Image(systemName: "bird.fill")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(.primary)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startSplashAnimation()
        }
    }

    private func startSplashAnimation() {
        // Phase 1: Logo springs into view
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Phase 2: Logo zooms toward user while splash fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                logoScale = 12.0
                logoOpacity = 0
                splashBackgroundOpacity = 0
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title2.bold())

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                Task { await initializeState() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
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
    @State private var selectedTab: AppTab = .feed
    @State private var hasCheckedFollows = false
    @State private var showComposer = false

    enum AppTab: String, CaseIterable {
        case feed
        case explore
        case wallet
        case profile
        case settings
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    FeedView()
                }
                .tag(AppTab.feed)
                .tabItem { Label("Feed", systemImage: "house.fill") }

                NavigationStack {
                    ExploreView()
                }
                .tag(AppTab.explore)
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }

                NavigationStack {
                    WalletView()
                }
                .tag(AppTab.wallet)
                .tabItem { Label("Wallet", systemImage: "wallet.bifold.fill") }

                NavigationStack {
                    ProfileView()
                }
                .tag(AppTab.profile)
                .tabItem { Label("Profile", systemImage: "person.fill") }

                NavigationStack {
                    SettingsView()
                }
                .tag(AppTab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
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

            // FAB Button for composing new posts (only on Feed tab)
            if state.authManager.isAuthenticated && selectedTab == .feed {
                fabButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showComposer) {
            ComposerView(ndk: state.ndk)
        }
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button {
            showComposer = true
        } label: {
            fabLabel
        }
        .buttonStyle(FABButtonStyle())
    }

    @ViewBuilder
    private var fabLabel: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(ChirpGradients.primary)
                }
                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - FAB Button Style

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
