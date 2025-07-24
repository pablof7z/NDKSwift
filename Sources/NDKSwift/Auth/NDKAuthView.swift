import SwiftUI
import LocalAuthentication

// MARK: - Constants

/// Icon size for authentication view icons
private let authIconSize: CGFloat = 60

/// SwiftUI view for NDK authentication flow
///
/// Provides a declarative interface for authentication that automatically handles
/// session restoration, multi-account management, and authentication states.
/// Integrates seamlessly with the NDKAuthManager using modern @Observable pattern.
///
/// ## Usage
///
/// ```swift
/// struct ContentView: View {
///     @State private var authManager = NDKAuthManager.shared
///
///     var body: some View {
///         NDKAuthView(authManager: authManager) {
///             // Authenticated content
///             MainAppView()
///         } authenticationView: {
///             // Custom login UI
///             LoginView()
///         }
///     }
/// }
/// ```
///
/// ## Features
///
/// - **Automatic State Management**: Handles all authentication states
/// - **Session Restoration**: Automatically restores sessions on app launch
/// - **Biometric Integration**: Built-in Face ID/Touch ID support
/// - **Multi-Account Support**: Account switching UI
/// - **Customizable**: Override authentication UI as needed
public struct NDKAuthView<AuthenticatedContent: View, AuthenticationContent: View>: View {
    
    // MARK: - Properties
    
    /// The authentication manager
    @Bindable private var authManager: NDKAuthManager
    
    /// Content to show when authenticated
    private let authenticatedContent: () -> AuthenticatedContent
    
    /// Content to show when not authenticated
    private let authenticationContent: () -> AuthenticationContent
    
    /// Optional NDK instance to set on auth manager
    private let ndk: NDK?
    
    // MARK: - State
    
    @State private var showingAccountPicker = false
    @State private var showingBiometricPrompt = false
    @State private var biometricError: Error?
    @State private var sessionSwitchError: Error?
    @State private var switchingSession: NDKSession?
    
    // MARK: - Initialization
    
    /// Initialize NDKAuthView with custom authentication content
    /// - Parameters:
    ///   - authManager: The authentication manager to use
    ///   - ndk: Optional NDK instance
    ///   - authenticatedContent: Content to show when authenticated
    ///   - authenticationContent: Content to show when not authenticated
    @MainActor
    public init(
        authManager: NDKAuthManager,
        ndk: NDK? = nil,
        @ViewBuilder authenticatedContent: @escaping () -> AuthenticatedContent,
        @ViewBuilder authenticationContent: @escaping () -> AuthenticationContent
    ) {
        self.authManager = authManager
        self.ndk = ndk
        self.authenticatedContent = authenticatedContent
        self.authenticationContent = authenticationContent
    }
    
    /// Convenience initializer with default auth manager
    @MainActor
    public init(
        ndk: NDK? = nil,
        @ViewBuilder authenticatedContent: @escaping () -> AuthenticatedContent,
        @ViewBuilder authenticationContent: @escaping () -> AuthenticationContent
    ) {
        self.init(
            authManager: .shared,
            ndk: ndk,
            authenticatedContent: authenticatedContent,
            authenticationContent: authenticationContent
        )
    }
    
    /// Initialize NDKAuthView with default authentication UI
    /// - Parameters:
    ///   - authManager: The authentication manager to use
    ///   - ndk: Optional NDK instance
    ///   - authenticatedContent: Content to show when authenticated
    @MainActor
    public init(
        authManager: NDKAuthManager,
        ndk: NDK? = nil,
        @ViewBuilder authenticatedContent: @escaping () -> AuthenticatedContent
    ) where AuthenticationContent == DefaultAuthenticationView {
        self.authManager = authManager
        self.ndk = ndk
        self.authenticatedContent = authenticatedContent
        self.authenticationContent = { DefaultAuthenticationView() }
    }
    
    /// Convenience initializer with default auth manager and default authentication UI
    @MainActor
    public init(
        ndk: NDK? = nil,
        @ViewBuilder authenticatedContent: @escaping () -> AuthenticatedContent
    ) where AuthenticationContent == DefaultAuthenticationView {
        self.init(
            authManager: .shared,
            ndk: ndk,
            authenticatedContent: authenticatedContent
        )
    }
    
    // MARK: - Body
    
    public var body: some View {
        Group {
            switch authManager.authenticationState {
            case .authenticated:
                authenticatedContent()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .authenticating:
                authenticatingView
                
            case .biometricRequired:
                biometricRequiredView
                
            case .unauthenticated:
                // Only show session selection if we have sessions AND we're not in the process of authenticating
                // This prevents the "Welcome Back" screen from appearing during login/signup flow
                if authManager.hasSessions && !isActivelyAuthenticating() {
                    sessionSelectionView
                } else {
                    authenticationContent()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
            case .authenticationFailed(let error):
                errorView(error)
                
            case .sessionExpired:
                sessionExpiredView
            }
        }
        .onAppear {
            setupAuthManager()
        }
        .sheet(isPresented: $showingAccountPicker) {
            AccountPickerView(authManager: authManager)
        }
        .alert("Biometric Authentication Failed", isPresented: .constant(biometricError != nil)) {
            let errorInfo = biometricError.map { NDKAuthErrorHandler.analyze($0) }
            
            if errorInfo?.isRecoverable == true {
                Button("Retry") {
                    biometricError = nil
                    retryBiometricAuth()
                }
            }
            Button("Cancel") {
                biometricError = nil
                authManager.logout()
            }
        } message: {
            if let error = biometricError {
                let errorInfo = NDKAuthErrorHandler.analyze(error)
                Text(errorInfo.message)
            }
        }
        .alert(isPresented: .constant(sessionSwitchError != nil)) {
            let errorInfo = sessionSwitchError.map { NDKAuthErrorHandler.analyze($0) }
            
            return Alert(
                title: Text(errorInfo?.title ?? "Error"),
                message: Text(errorInfo?.message ?? "An unexpected error occurred."),
                primaryButton: .default(Text("OK")) {
                    sessionSwitchError = nil
                },
                secondaryButton: errorInfo?.suggestedAction == .removeAccount
                    ? .destructive(Text("Remove Account")) {
                        sessionSwitchError = nil
                        // Account has already been cleaned up in handleSessionSwitch
                    }
                    : .cancel(Text("Cancel")) {
                        sessionSwitchError = nil
                    }
            )
        }
    }
    
    // MARK: - State Views
    
    private var authenticatingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Restoring session...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    private var biometricRequiredView: some View {
        VStack(spacing: 30) {
            biometricIcon
            
            VStack(spacing: 12) {
                Text("Authentication Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Use \(biometricTypeText) to access your account")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: retryBiometricAuth) {
                Label("Authenticate", systemImage: biometricSystemImage)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            
            Button("Use Different Account") {
                authManager.logout()
            }
            .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    private var sessionSelectionView: some View {
        VStack(spacing: 30) {
            sessionSelectionHeader
            sessionsList
            addAccountButton
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    private var sessionSelectionHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: authIconSize))
                .foregroundStyle(.blue)
            
            Text("Welcome Back")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Choose an account to continue")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
    
    private var sessionsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(authManager.availableSessions.prefix(3)) { session in
                SessionRowView(
                    session: session,
                    isLoading: switchingSession?.id == session.id
                ) {
                    handleSessionSwitch(session)
                }
            }
            
            if authManager.availableSessions.count > 3 {
                Button("View All Accounts (\(authManager.availableSessions.count))") {
                    showingAccountPicker = true
                }
                .foregroundStyle(.blue)
            }
        }
    }
    
    private var addAccountButton: some View {
        Button("Add New Account") {
            // Switch to authentication content
            authManager.logout()
        }
        .foregroundStyle(.secondary)
    }
    
    private func handleSessionSwitch(_ session: NDKSession) {
        Task {
            switchingSession = session
            sessionSwitchError = nil
            do {
                try await authManager.switchToSession(session)
                switchingSession = nil
            } catch {
                let errorInfo = NDKAuthErrorHandler.analyze(error)
                
                // If it's a corrupted session error, the auth manager has already cleaned up
                if errorInfo.suggestedAction == .removeAccount {
                    // Just logout to allow fresh login
                    authManager.logout()
                }
                
                sessionSwitchError = error
                switchingSession = nil
            }
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        return VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            VStack(spacing: 8) {
                Text(errorInfo.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(errorInfo.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if errorInfo.isRecoverable {
                Button("Try Again") {
                    authManager.restoreSession()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Sign In") {
                    authManager.logout()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    private var sessionExpiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            VStack(spacing: 8) {
                Text("Session Expired")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Please sign in again to continue")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            Button("Sign In") {
                authManager.logout()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
    
    
    // MARK: - Biometric Support
    
    private var biometricIcon: some View {
        Image(systemName: biometricSystemImage)
            .font(.system(size: 60))
            .foregroundStyle(.blue)
    }
    
    private var biometricSystemImage: String {
        #if !os(watchOS)
        switch authManager.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "lock.shield"
        }
        #else
        return "lock.shield"
        #endif
    }
    
    private var biometricTypeText: String {
        #if !os(watchOS)
        switch authManager.biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "biometric authentication"
        }
        #else
        return "authentication"
        #endif
    }
    
    // MARK: - Private Methods
    
    private func setupAuthManager() {
        if let ndk = ndk {
            authManager.setNDK(ndk)
        }
    }
    
    /// Check if we're actively in an authentication flow
    /// This helps prevent showing session selection during login/signup
    private func isActivelyAuthenticating() -> Bool {
        // If we have an active session that was just created (within last 2 seconds)
        // we're likely in the middle of an auth flow
        if let activeSession = authManager.activeSession,
           Date().timeIntervalSince(activeSession.lastUsed) < 2.0 {
            return true
        }
        return false
    }
    
    private func retryBiometricAuth() {
        guard let activeSession = authManager.activeSession else { return }
        
        Task {
            do {
                try await authManager.switchToSession(activeSession)
            } catch {
                biometricError = error
            }
        }
    }
}

// MARK: - Session Row View

private struct SessionRowView: View {
    let session: NDKSession
    let isLoading: Bool
    let action: () -> Void
    
    init(session: NDKSession, isLoading: Bool = false, action: @escaping () -> Void) {
        self.session = session
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Avatar or placeholder
                AsyncImage(url: session.avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .overlay(
                            Text((session.profileName ?? "?").prefix(1).uppercased())
                                .font(.title3)
                                .fontWeight(.medium)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.profileName ?? session.shortIdentifier)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(session.shortIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if session.requiresBiometric || session.isHardwareBacked {
                        HStack(spacing: 4) {
                            if session.isHardwareBacked {
                                Image(systemName: "checkmark.shield")
                                    .foregroundStyle(.green)
                            }
                            if session.requiresBiometric {
                                Image(systemName: "faceid")
                                    .foregroundStyle(.blue)
                            }
                            Text(session.securityLevel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1.0)
    }
}

// MARK: - Account Picker View

private struct AccountPickerView: View {
    @Bindable var authManager: NDKAuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var switchingSession: NDKSession?
    
    var body: some View {
        NavigationView {
            accountList
                .navigationTitle("Accounts")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Account") {
                            authManager.logout()
                            dismiss()
                        }
                    }
                }
        }
    }
    
    private var accountList: some View {
        List {
            ForEach(authManager.availableSessions) { session in
                SessionRowView(
                    session: session,
                    isLoading: switchingSession?.id == session.id
                ) {
                    handleAccountSwitch(session)
                }
            }
            .onDelete(perform: deleteSessions)
        }
    }
    
    private func handleAccountSwitch(_ session: NDKSession) {
        Task {
            switchingSession = session
            do {
                try await authManager.switchToSession(session)
                dismiss()
            } catch {
                let errorInfo = NDKAuthErrorHandler.analyze(error)
                
                // If it's a corrupted session error, the auth manager has already cleaned up
                if errorInfo.suggestedAction == .removeAccount {
                    // Just dismiss and logout to allow fresh login
                    dismiss()
                    authManager.logout()
                } else {
                    // Error will be shown by parent view
                    switchingSession = nil
                }
            }
        }
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = authManager.availableSessions[index]
            Task {
                try await authManager.deleteSession(session)
            }
        }
    }
}

// MARK: - Default Authentication View

/// Default authentication view when none is provided
public struct DefaultAuthenticationView: View {
    public init() {}
    
    public var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: authIconSize))
                    .foregroundStyle(.blue)
                
                Text("Authentication Required")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Please provide your authentication UI")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Text("To use NDKAuthView, provide your own authentication content:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("""
                NDKAuthView {
                    MainAppView()
                } authenticationView: {
                    YourLoginView()
                }
                """)
                .font(.caption)
                .fontDesign(.monospaced)
                .padding()
                .background(.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}