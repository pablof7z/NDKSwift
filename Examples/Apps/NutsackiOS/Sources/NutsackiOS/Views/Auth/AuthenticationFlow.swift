import SwiftUI
import NDKSwift

struct AuthenticationFlow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.dismiss) private var dismiss
    
    // Wizard state
    enum WizardStep {
        case welcome
        case createAccount
        case importAccount
        case setupRelays
        case setupMints
    }
    
    @State private var currentStep: WizardStep = .welcome
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Account creation fields
    @State private var displayName = ""
    @State private var about = ""
    
    // Import fields
    @State private var nsecInput = ""
    @State private var showPassword = false
    @State private var showScanner = false
    
    // Setup fields
    @State private var selectedRelays: Set<String> = []
    @State private var selectedMints: Set<String> = []
    @State private var discoveredMints: [DiscoveredMint] = []
    @State private var isDiscoveringMints = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome {
                    progressIndicator
                        .padding(.top, 10)
                        .padding(.horizontal)
                }
                
                // Main content
                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeView
                    case .createAccount:
                        createAccountView
                    case .importAccount:
                        importAccountView
                    case .setupRelays:
                        relaySelectionView
                    case .setupMints:
                        mintSelectionView
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Navigation buttons
                if currentStep != .welcome {
                    navigationButtons
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                }
            }
            .background(backgroundGradient)
            .navigationBarHidden(true)
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
        .task {
            setupMintDiscovery()
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 12) {
            ForEach(progressSteps, id: \.self) { index in
                Capsule()
                    .fill(stepIndex >= index ? Color.orange : Color.white.opacity(0.2))
                    .frame(width: stepIndex == index ? 32 : 16, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: stepIndex)
            }
        }
    }
    
    private var progressSteps: [Int] {
        switch currentStep {
        case .welcome:
            return []
        case .createAccount, .importAccount:
            return [0, 1, 2]
        case .setupRelays:
            return [0, 1, 2]
        case .setupMints:
            return [0, 1, 2]
        }
    }
    
    private var stepIndex: Int {
        switch currentStep {
        case .welcome:
            return -1
        case .createAccount, .importAccount:
            return 0
        case .setupRelays:
            return 1
        case .setupMints:
            return 2
        }
    }
    
    // MARK: - Welcome View
    
    private var welcomeView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Logo
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.8),
                                Color.purple.opacity(0.4),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 280, height: 280)
                    .blur(radius: 30)
                
                // Hexagon nut logo
                HexagonShape()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color.orange.opacity(0.9),
                                Color(red: 0.8, green: 0.4, blue: 0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .mask(
                        ZStack {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 280, height: 280)
                            
                            Circle()
                                .fill(Color.black)
                                .frame(width: 56, height: 56)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    )
                    .shadow(color: Color.orange.opacity(0.5), radius: 20, x: 0, y: 5)
            }
            
            // Title
            VStack(spacing: 8) {
                Text("NUTSACK")
                    .font(.system(size: 52, weight: .black, design: .default))
                    .tracking(4)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white, Color.white.opacity(0.9)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("A WALLET FOR THE RELAYS")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .tracking(2)
                    .foregroundColor(Color.white.opacity(0.5))
            }
            
            Spacer()
            
            // Buttons
            VStack(spacing: 16) {
                Button(action: { currentStep = .createAccount }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20))
                        Text("New Account")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color(red: 0.9, green: 0.5, blue: 0.1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                }
                
                Button(action: { currentStep = .importAccount }) {
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.system(size: 20))
                        Text("Login")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                Text("Your keys, your nuts")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Create Account View
    
    private var createAccountView: some View {
        VStack(spacing: 30) {
            Text("Create Account")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 40)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    TextField("", text: $displayName)
                        .textFieldStyle(DarkTextFieldStyle())
                        .textContentType(.name)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About (optional)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    TextField("", text: $about, axis: .vertical)
                        .textFieldStyle(DarkTextFieldStyle())
                        .lineLimit(3...6)
                }
                
                Text("This information will be public on Nostr")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Import Account View
    
    private var importAccountView: some View {
        VStack(spacing: 30) {
            Text("Import Account")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 40)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
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
                                    .foregroundColor(Color.white.opacity(0.6))
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .accentColor(.orange)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button(action: { showScanner = true }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.4))
                        
                        Text("Your key is stored securely on this device")
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Relay Selection View
    
    private var relaySelectionView: some View {
        VStack(spacing: 30) {
            Text("Select Relays")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 40)
            
            Text("Choose relays to connect to the Nostr network")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(suggestedRelays, id: \.url) { relay in
                        RelaySelectionRow(
                            relay: relay,
                            isSelected: selectedRelays.contains(relay.url),
                            onToggle: {
                                if selectedRelays.contains(relay.url) {
                                    selectedRelays.remove(relay.url)
                                } else {
                                    selectedRelays.insert(relay.url)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - Mint Selection View
    
    private var mintSelectionView: some View {
        VStack(spacing: 30) {
            Text("Select Mints")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 40)
            
            Text("Choose Cashu mints for your ecash wallet")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            if discoveredMints.isEmpty && isDiscoveringMints {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.orange)
                    Text("Discovering mints...")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(discoveredMints) { mint in
                            MintSelectionRow(
                                mint: mint,
                                isSelected: selectedMints.contains(mint.url),
                                onToggle: {
                                    if selectedMints.contains(mint.url) {
                                        selectedMints.remove(mint.url)
                                    } else {
                                        selectedMints.insert(mint.url)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            // Back button
            Button(action: navigateBack) {
                Text("Back")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            
            Spacer()
            
            // Next/Complete button
            Button(action: navigateNext) {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(nextButtonTitle)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(minWidth: 120)
            .frame(height: 56)
            .background(nextButtonBackground)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: isNextButtonEnabled ? Color.orange.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 4)
            .disabled(!isNextButtonEnabled || isProcessing)
        }
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome:
            return ""
        case .createAccount:
            return "Next"
        case .importAccount:
            return "Next"
        case .setupRelays:
            return "Next"
        case .setupMints:
            return "Complete"
        }
    }
    
    private var nextButtonBackground: LinearGradient {
        if isNextButtonEnabled {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color.orange,
                    Color(red: 0.9, green: 0.5, blue: 0.1)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    private var isNextButtonEnabled: Bool {
        switch currentStep {
        case .welcome:
            return false
        case .createAccount:
            return !displayName.isEmpty
        case .importAccount:
            return !nsecInput.isEmpty
        case .setupRelays:
            return !selectedRelays.isEmpty
        case .setupMints:
            return !selectedRelays.isEmpty // Can complete without mints
        }
    }
    
    // MARK: - Navigation Methods
    
    private func navigateBack() {
        switch currentStep {
        case .welcome:
            break
        case .createAccount, .importAccount:
            currentStep = .welcome
            // Clear form data
            displayName = ""
            about = ""
            nsecInput = ""
            showPassword = false
        case .setupRelays:
            if displayName.isEmpty {
                currentStep = .importAccount
            } else {
                currentStep = .createAccount
            }
        case .setupMints:
            currentStep = .setupRelays
        }
    }
    
    private func navigateNext() {
        switch currentStep {
        case .welcome:
            break
        case .createAccount:
            createAccount()
        case .importAccount:
            importAccount()
        case .setupRelays:
            currentStep = .setupMints
        case .setupMints:
            completeSetup()
        }
    }
    
    // MARK: - Actions
    
    private func createAccount() {
        isProcessing = true
        
        Task {
            do {
                _ = try await nostrManager.createNewAccount(
                    displayName: displayName,
                    about: about.isEmpty ? nil : about
                )
                
                await MainActor.run {
                    isProcessing = false
                    currentStep = .setupRelays
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func importAccount() {
        isProcessing = true
        
        Task {
            do {
                let signer = try NDKPrivateKeySigner(nsec: nsecInput)
                let pubkey = try await signer.pubkey
                
                var displayName = "Nostr User"
                
                if let ndk = nostrManager.ndk {
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
                            break
                        }
                    }
                }
                
                let _ = try await nostrManager.createAccountFromNsec(
                    nsecInput,
                    displayName: displayName
                )
                
                await MainActor.run {
                    isProcessing = false
                    currentStep = .setupRelays
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func completeSetup() {
        isProcessing = true
        
        Task {
            do {
                guard let wallet = walletManager.activeWallet else {
                    throw NSError(domain: "WalletSetup", code: 0, userInfo: [NSLocalizedDescriptionKey: "No active wallet found"])
                }
                
                // Setup wallet with selected relays and mints
                try await wallet.setup(
                    mints: Array(selectedMints),
                    relays: Array(selectedRelays),
                    publishMintList: true
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func setupMintDiscovery() {
        guard let ndk = nostrManager.ndk else { return }
        
        Task {
            isDiscoveringMints = true
            
            let discoveryManager = MintDiscoveryManager(ndk: ndk)
            
            for await mints in discoveryManager.discoverMintsStream() {
                await MainActor.run {
                    self.discoveredMints = mints
                    if !mints.isEmpty {
                        isDiscoveringMints = false
                    }
                }
            }
            
            await MainActor.run {
                isDiscoveringMints = false
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.02, blue: 0.08),
                Color(red: 0.02, green: 0.01, blue: 0.03),
                Color.black
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Supporting Views

struct RelaySelectionRow: View {
    let relay: RelayInfo
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(relay.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(relay.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .orange : .white.opacity(0.3))
            }
            .padding()
            .background(Color.white.opacity(isSelected ? 0.15 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MintSelectionRow: View {
    let mint: DiscoveredMint
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mint.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    if let description = mint.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    Text(mint.url)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .orange : .white.opacity(0.3))
            }
            .padding()
            .background(Color.white.opacity(isSelected ? 0.15 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggested Relays

private let suggestedRelays = [
    RelayInfo(url: "wss://relay.primal.net", name: "Primal", description: "Fast and reliable public relay"),
    RelayInfo(url: "wss://relay.damus.io", name: "Damus", description: "Popular iOS-friendly relay"),
    RelayInfo(url: "wss://nos.lol", name: "nos.lol", description: "High-performance relay"),
    RelayInfo(url: "wss://relay.nostr.band", name: "Nostr Band", description: "Analytics and search relay"),
    RelayInfo(url: "wss://relay.nostr.wine", name: "Nostr Wine", description: "Paid relay with spam protection")
]

