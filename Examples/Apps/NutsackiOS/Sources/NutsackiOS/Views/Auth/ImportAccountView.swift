import SwiftUI
import SwiftData
import NDKSwift

struct ImportAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var nsecInput = ""
    @State private var isLoggingIn = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showScanner = false
    @State private var profileTask: Task<Void, Never>?
    @State private var keyFieldOpacity: Double = 0
    @State private var showPassword = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground).opacity(0.5)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header section
                        VStack(spacing: 24) {
                            // Icon with glow effect
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            gradient: Gradient(colors: [
                                                Color.orange.opacity(0.3),
                                                Color.orange.opacity(0)
                                            ]),
                                            center: .center,
                                            startRadius: 5,
                                            endRadius: 60
                                        )
                                    )
                                    .frame(width: 120, height: 120)
                                    .blur(radius: 10)
                                
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.orange.opacity(0.9),
                                                Color.orange
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "key.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            }
                            .padding(.top, 40)
                            
                            VStack(spacing: 8) {
                                Text("Welcome Back")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                
                                Text("Enter your private key to continue")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Input section
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Private Key")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    HStack {
                                        if showPassword {
                                            TextField("nsec1...", text: $nsecInput)
                                                .textContentType(.password)
                                                #if os(iOS)
                                                .textInputAutocapitalization(.never)
                                                #endif
                                                .font(.system(.body, design: .monospaced))
                                        } else {
                                            SecureField("nsec1...", text: $nsecInput)
                                                .textContentType(.password)
                                                #if os(iOS)
                                                .textInputAutocapitalization(.never)
                                                #endif
                                                .font(.system(.body, design: .monospaced))
                                        }
                                        
                                        Button(action: { showPassword.toggle() }) {
                                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor.tertiarySystemFill))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(
                                                        nsecInput.isEmpty ? Color.clear : Color.orange.opacity(0.5),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                    
                                    Button(action: { showScanner = true }) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(UIColor.tertiarySystemFill))
                                                .frame(width: 50, height: 50)
                                            
                                            Image(systemName: "qrcode.viewfinder")
                                                .font(.title2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .opacity(keyFieldOpacity)
                                
                                HStack {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Your key is stored securely on this device")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            
                            // Login button
                            Button(action: loginWithAccount) {
                                ZStack {
                                    if isLoggingIn {
                                        HStack(spacing: 12) {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.9)
                                            
                                            Text("Logging in...")
                                                .fontWeight(.semibold)
                                        }
                                    } else {
                                        HStack {
                                            Image(systemName: "arrow.right.circle.fill")
                                            Text("Log In")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.orange,
                                                    Color.orange.opacity(0.8)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .opacity(nsecInput.isEmpty ? 0.5 : 1)
                                )
                                .disabled(nsecInput.isEmpty || isLoggingIn)
                                .scaleEffect(nsecInput.isEmpty ? 0.98 : 1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: nsecInput.isEmpty)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Log In")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedValue in
                    nsecInput = scannedValue
                    showScanner = false
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                    keyFieldOpacity = 1
                }
            }
            .onDisappear {
                profileTask?.cancel()
            }
        }
    }
    
    private func loginWithAccount() {
        print("🔑 [ImportAccountView] loginWithAccount() called")
        
        // Add haptic feedback
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isLoggingIn = true
        }
        
        Task {
            do {
                print("🔑 [ImportAccountView] Logging in with nsec...")
                // Create signer to get pubkey and fetch profile
                let signer = try NDKPrivateKeySigner(nsec: nsecInput)
                let pubkey = try await signer.pubkey
                
                // Observe the user's profile (kind 0) to get their display name
                print("🔑 [ImportAccountView] Observing profile for pubkey: \(pubkey)")
                var displayName = "Nostr User"
                
                if let ndk = nostrManager.ndk {
                    // Use declarative data source for profile
                    let profileDataSource = ndk.observe(
                        filter: NDKFilter(
                            authors: [pubkey],
                            kinds: [0]
                        ),
                        maxAge: 3600,
                        cachePolicy: .cacheWithNetwork
                    )
                    
                    for await event in profileDataSource.events {
                        if let profileData = event.content.data(using: .utf8),
                           let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
                            displayName = profile.displayName ?? profile.name ?? "Nostr User"
                            print("🔑 [ImportAccountView] Using display name: \(displayName)")
                            break // We only need the first profile for login
                        }
                    }
                }
                
                // Create session using NDKAuth system
                print("🔑 [ImportAccountView] Creating session...")
                let session = try await nostrManager.createAccountFromNsec(
                    nsecInput,
                    displayName: displayName
                )
                print("🔑 [ImportAccountView] Session created successfully: \(session.id)")
                
                await MainActor.run {
                    print("🔑 [ImportAccountView] Login successful, waiting for auth state to stabilize...")
                    
                    // Success haptic feedback
                    #if os(iOS)
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    #endif
                    
                    // Ensure the auth state is fully propagated before dismissing
                    // This prevents the "Welcome Back" screen from briefly appearing
                    Task {
                        // Wait a moment for the auth state to stabilize
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        print("🔑 [ImportAccountView] Dismissing view")
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLoggingIn = false
                        }
                        
                        dismiss()
                    }
                }
            } catch {
                print("🔑 [ImportAccountView] Login error: \(error)")
                await MainActor.run {
                    // Error haptic feedback
                    #if os(iOS)
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    #endif
                    
                    errorMessage = error.localizedDescription
                    showError = true
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoggingIn = false
                    }
                }
            }
        }
    }
}