import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var authManager = NDKAuthManager.shared
    @State private var selectedTab = Tab.home
    @State private var tabBarVisible = true
    
    enum Tab: CaseIterable {
        case home, discover, create, library, profile
    }
    
    var body: some View {
        if authManager.isAuthenticated {
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case .home:
                        HomeView(tabBarVisible: $tabBarVisible)
                    case .discover:
                        SearchView()
                    case .create:
                        CreateHighlightView()
                    case .library:
                        LibraryView()
                    case .profile:
                        ProfileView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .animation(.highlighterEase, value: selectedTab)
                
                if tabBarVisible {
                    CustomTabBar(selectedTab: $selectedTab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: tabBarVisible)
                }
            }
            .background(
                AnimatedGradientBackground(colors: [
                    Color.highlighterBackground,
                    Color(uiColor: .secondarySystemBackground).opacity(0.05),
                    Color.highlighterBackground
                ])
            )
        } else {
            AuthenticationView()
                .transition(.opacity.combined(with: .scale))
        }
    }
}

// MARK: - Enhanced Authentication View

struct AuthenticationView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImportSheet = false
    @State private var privateKey = ""
    @State private var isCreatingAccount = false
    @State private var viewAppeared = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                VStack(spacing: 48) {
                    Spacer()
                    
                    logoSection
                        .fadeSlide(isVisible: viewAppeared, delay: 0)
                    
                    Spacer()
                    
                    actionButtons
                        .fadeSlide(isVisible: viewAppeared, delay: 0.2)
                    
                    Spacer()
                }
                .sheet(isPresented: $showImportSheet) {
                    ImportAccountSheet(privateKey: $privateKey, onImport: importAccount)
                }
                .overlay(loadingOverlay)
            }
        }
        .onAppear {
            withAnimation {
                viewAppeared = true
            }
        }
    }
    
    @ViewBuilder
    private var logoSection: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .blur(radius: 40)
                    .opacity(0.5)
                
                Image(systemName: "highlighter")
                    .font(.system(size: 80))
                    .foregroundStyle(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .rotationEffect(.degrees(-45))
                    .shimmer()
            }
            
            VStack(spacing: 8) {
                Text("Highlighter")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Illuminate the best ideas")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.highlighterSecondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 16) {
            Button(action: createAccount) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Create Account")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(
                    color: Color.highlighterOrange.opacity(0.3),
                    radius: 12,
                    x: 0,
                    y: 0
                )
            }
            .buttonStyle(PressButtonStyle())
            .disabled(isCreatingAccount)
            
            Button(action: { showImportSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text("Import Account")
                        .font(.system(size: 16, weight: .regular))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(.ultraThinMaterial)
                .foregroundColor(.highlighterText)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .buttonStyle(PressButtonStyle())
        }
        .padding(.horizontal, 32)
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if isCreatingAccount {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            
            VStack(spacing: 24) {
                LoadingDots()
                    .scaleEffect(1.5)
                
                Text("Creating your account...")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.highlighterSecondaryText)
            }
            .padding(32)
            .glassBackground()
            .transition(AnyTransition.scale.combined(with: .opacity))
        }
    }
    
    private func createAccount() {
        isCreatingAccount = true
        HapticType.medium.trigger()
        
        Task {
            do {
                try await appState.createAccount()
                HapticType.success.trigger()
            } catch {
                HapticType.error.trigger()
            }
            isCreatingAccount = false
        }
    }
    
    private func importAccount() {
        HapticType.medium.trigger()
        
        Task {
            do {
                try await appState.importAccount(nsec: privateKey)
                HapticType.success.trigger()
                showImportSheet = false
            } catch {
                HapticType.error.trigger()
            }
        }
    }
}

// MARK: - Enhanced Import Account Sheet

struct ImportAccountSheet: View {
    @Binding var privateKey: String
    let onImport: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showSecurely = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    
                    instructionSection
                    
                    inputSection
                    
                    importButton
                    
                    Spacer(minLength: 48)
                }
                .padding(24)
            }
            .background(Color.highlighterBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Import Account")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        HapticType.selection.trigger()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .regular))
                }
            }
        }
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.bottom, 8)
            
            Text("Import Your Nostr Account")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        }
    }
    
    @ViewBuilder
    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter your private key to access your existing account.")
                .font(.highlighterBody)
                .foregroundColor(Color.highlighterSecondaryText)
            
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(Color.highlighterOrange)
                Text("Your key is stored securely on this device")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.highlighterSecondaryText)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.highlighterOrange.opacity(0.1))
            )
        }
    }
    
    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Private Key")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.highlighterSecondaryText)
                
                Spacer()
                
                Button(action: { showSecurely.toggle() }) {
                    Image(systemName: showSecurely ? "eye.slash" : "eye")
                        .font(.system(size: 16))
                        .foregroundColor(Color.highlighterOrange)
                }
            }
            
            Group {
                if showSecurely {
                    TextField("nsec1...", text: $privateKey)
                } else {
                    SecureField("nsec1...", text: $privateKey)
                }
            }
            .textFieldStyle(ModernTextFieldStyle())
            .autocapitalization(.none)
            .disableAutocorrection(true)
        }
    }
    
    @ViewBuilder
    private var importButton: some View {
        Button(action: {
            HapticType.medium.trigger()
            onImport()
        }) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text("Import Account")
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: Color.highlighterOrange.opacity(0.3),
                radius: 12,
                x: 0,
                y: 0
            )
        }
        .buttonStyle(PressButtonStyle())
        .disabled(privateKey.isEmpty || !privateKey.hasPrefix("nsec"))
        .opacity(privateKey.isEmpty || !privateKey.hasPrefix("nsec") ? 0.6 : 1.0)
    }
}

// MARK: - Modern Text Field Style

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            )
            .font(.highlighterBody)
    }
}

// MARK: - Tab Extensions

extension ContentView.Tab {
    var icon: String {
        switch self {
        case .home: return "house"
        case .discover: return "magnifyingglass"
        case .create: return "highlighter"
        case .library: return "books.vertical"
        case .profile: return "person"
        }
    }
    
    var filledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .discover: return "magnifyingglass"
        case .create: return "highlighter"
        case .library: return "books.vertical.fill"
        case .profile: return "person.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .discover: return "Discover"
        case .create: return "Create"
        case .library: return "Library"
        case .profile: return "Profile"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}