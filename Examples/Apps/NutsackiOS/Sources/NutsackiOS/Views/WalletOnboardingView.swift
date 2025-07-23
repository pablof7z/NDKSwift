import SwiftUI
import NDKSwift
import SwiftData

struct WalletOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var walletManager
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var currentStep = 0
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = -180
    @State private var glowOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 50
    @State private var electricityOffset: CGFloat = -100
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    
    @State private var selectedRelays: Set<String> = []
    @State private var selectedMints: Set<String> = []
    @State private var isSettingUpWallet = false
    @State private var setupError: String?
    @State private var showError = false
    
    // Mint discovery
    @State private var discoveredMints: [DiscoveredMint] = []
    @State private var isDiscoveringMints = false
    
    private var currentTitle: String {
        switch currentStep {
        case 0: return "SETUP"
        case 1: return "RELAYS"
        case 2: return "MINTS"
        default: return ""
        }
    }
    
    // Default relay suggestions
    let suggestedRelays = [
        RelayInfo(url: "wss://relay.primal.net", name: "Primal", description: "Fast and reliable public relay"),
        RelayInfo(url: "wss://relay.damus.io", name: "Damus", description: "Popular iOS-friendly relay"),
        RelayInfo(url: "wss://nos.lol", name: "nos.lol", description: "High-performance relay"),
        RelayInfo(url: "wss://relay.nostr.band", name: "Nostr Band", description: "Analytics and search relay"),
        RelayInfo(url: "wss://nostr.wine", name: "Nostr Wine", description: "Paid relay with spam protection")
    ]
    
    
    var body: some View {
        ZStack {
            // Dark gradient background
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
            
            // Electric field effect
            ForEach(0..<3) { index in
                ElectricArc(
                    startPoint: CGPoint(x: 0.5, y: 0.5),
                    endPoint: CGPoint(
                        x: 0.5 + cos(Double(index) * .pi / 1.5) * 0.3,
                        y: 0.5 + sin(Double(index) * .pi / 1.5) * 0.3
                    )
                )
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.4),
                            Color.purple.opacity(0.2),
                            Color.clear
                        ]),
                        startPoint: .center,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .blur(radius: 2)
                .opacity(glowOpacity * 0.5)
                .offset(y: electricityOffset)
                .animation(
                    .easeInOut(duration: 3)
                    .delay(Double(index) * 0.2)
                    .repeatForever(autoreverses: true),
                    value: electricityOffset
                )
            }
            
            VStack(spacing: 0) {
                // Compact header with logo and title side by side
                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 20) {
                        // Logo section
                        ZStack {
                            // Glow effect
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            Color.orange.opacity(0.6),
                                            Color.purple.opacity(0.3),
                                            Color.clear
                                        ]),
                                        center: .center,
                                        startRadius: 5,
                                        endRadius: 40
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .blur(radius: 15)
                                .scaleEffect(pulseScale)
                                .opacity(logoOpacity * 0.7)
                            
                            // Logo background
                            Circle()
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
                                .frame(width: 60, height: 60)
                                .shadow(color: Color.orange.opacity(0.5), radius: 10, x: 0, y: 2)
                                .scaleEffect(logoScale)
                                .opacity(logoOpacity)
                                .rotationEffect(.degrees(logoRotation))
                            
                            // Nut logo
                            NutLogoView(size: 35, color: .white)
                                .scaleEffect(logoScale)
                                .opacity(logoOpacity)
                                .rotationEffect(.degrees(logoRotation))
                        }
                        
                        // Title with animation
                        Text(currentTitle)
                            .font(.system(size: 40, weight: .black))
                            .tracking(2)
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white,
                                        Color.white.opacity(0.9)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 2)
                            .opacity(titleOpacity)
                            .offset(x: titleOffset)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentStep)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    
                    // Step indicator under the header
                    HStack(spacing: 12) {
                        ForEach(0..<3) { step in
                            Capsule()
                                .fill(currentStep >= step ? Color.orange : Color.white.opacity(0.2))
                                .frame(width: currentStep == step ? 32 : 16, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: currentStep)
                        }
                    }
                    .opacity(contentOpacity)
                }
                .padding(.top, 30)
                
                // Content
                VStack {
                    switch currentStep {
                    case 0:
                        WelcomeStepView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case 1:
                        RelaySelectionView(
                            selectedRelays: $selectedRelays,
                            suggestedRelays: suggestedRelays
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    case 2:
                        MintSelectionView(
                            selectedMints: $selectedMints,
                            discoveredMints: discoveredMints,
                            isDiscoveringMints: isDiscoveringMints
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .offset(y: contentOffset)
                .opacity(contentOpacity)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    if currentStep == 0 {
                        // Continue button
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentStep = 1
                            }
                        }) {
                            HStack {
                                Text("Continue")
                                    .font(.system(size: 18, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
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
                        
                        // Logout button
                        Button(action: {
                            Task {
                                await nostrManager.logout()
                                dismiss()
                            }
                        }) {
                            Text("Logout")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                    } else if currentStep == 1 {
                        // Next button for relay selection
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentStep = 2
                            }
                        }) {
                            HStack {
                                Text("Next: Select Mints")
                                    .font(.system(size: 18, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        selectedRelays.isEmpty ? Color.gray : Color.orange,
                                        selectedRelays.isEmpty ? Color.gray.opacity(0.8) : Color(red: 0.9, green: 0.5, blue: 0.1)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: selectedRelays.isEmpty ? Color.clear : Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                        }
                        .disabled(selectedRelays.isEmpty)
                        
                        // Back button
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentStep = 0
                            }
                        }) {
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                    } else if currentStep == 2 {
                        // Setup wallet button
                        Button(action: setupWallet) {
                            if isSettingUpWallet {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
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
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                    Text("Complete Setup")
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
                        }
                        .disabled(selectedRelays.isEmpty || isSettingUpWallet)
                        
                        // Back button
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentStep = 1
                            }
                        }) {
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .offset(y: contentOffset)
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            animateOnboarding()
            setupMintDiscovery()
        }
        .alert("Setup Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(setupError ?? "Failed to setup wallet")
        }
    }
    
    private func animateOnboarding() {
        // Logo animation
        withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
            logoScale = 1
            logoOpacity = 1
            logoRotation = 0
        }
        
        // Title animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.5)) {
            titleOpacity = 1
            titleOffset = 0
        }
        
        // Glow effects
        withAnimation(.easeInOut(duration: 1.2).delay(0.3)) {
            glowOpacity = 1
        }
        
        // Electricity animation
        withAnimation(.easeInOut(duration: 2).delay(0.5).repeatForever(autoreverses: true)) {
            electricityOffset = 100
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).delay(0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
        
        // Content animation
        withAnimation(.easeOut(duration: 0.8).delay(0.8)) {
            contentOffset = 0
            contentOpacity = 1
        }
    }
    
    private func setupMintDiscovery() {
        guard let ndk = nostrManager.ndk else { return }
        
        Task {
            isDiscoveringMints = true
            
            // Use MintDiscoveryManager to get mints
            let discoveryManager = MintDiscoveryManager(ndk: ndk)
            
            // Create an async stream to collect discovered mints
            for await mints in discoveryManager.discoverMintsStream() {
                await MainActor.run {
                    self.discoveredMints = mints
                    
                    // Stop discovering after getting a reasonable number of mints
                    if mints.count >= 5 {
                        isDiscoveringMints = false
                    }
                }
                
                // Break after first batch for onboarding
                if mints.count >= 5 {
                    break
                }
            }
            
            await MainActor.run {
                isDiscoveringMints = false
            }
        }
    }
    
    private func setupWallet() {
        guard !selectedRelays.isEmpty && !selectedMints.isEmpty else { return }
        
        isSettingUpWallet = true
        setupError = nil
        
        Task {
            do {
                guard let wallet = walletManager.activeWallet else {
                    throw NSError(domain: "WalletOnboarding", code: 0, userInfo: [NSLocalizedDescriptionKey: "No active wallet found"])
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
                    setupError = error.localizedDescription
                    showError = true
                    isSettingUpWallet = false
                }
            }
        }
    }
}

// MARK: - Welcome Step View
struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Let's set up your Cashu wallet to enable instant, private payments")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Feature highlights
            VStack(spacing: 20) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Lightning Fast",
                    description: "Instant payments with minimal fees"
                )
                
                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "Private & Secure",
                    description: "Your transactions stay private"
                )
                
                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Decentralized",
                    description: "No single point of failure"
                )
            }
            .padding(.top, 20)
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            
            Spacer()
        }
    }
}

// MARK: - Relay Selection View
struct RelaySelectionView: View {
    @Binding var selectedRelays: Set<String>
    let suggestedRelays: [RelayInfo]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select relays to sync your wallet data")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            // Relay list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(suggestedRelays, id: \.url) { relay in
                        OnboardingRelayRowView(
                            relay: relay,
                            isSelected: selectedRelays.contains(relay.url),
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if selectedRelays.contains(relay.url) {
                                        selectedRelays.remove(relay.url)
                                    } else {
                                        selectedRelays.insert(relay.url)
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 400)
            
            // Selection hint
            Text("\(selectedRelays.count) relay\(selectedRelays.count == 1 ? "" : "s") selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
        }
    }
}

// MARK: - Relay Row View
struct OnboardingRelayRowView: View {
    let relay: RelayInfo
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.orange : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 16, height: 16)
                    }
                }
                
                // Relay info
                VStack(alignment: .leading, spacing: 4) {
                    Text(relay.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(relay.description)
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.orange.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Relay Info
struct RelayInfo {
    let url: String
    let name: String
    let description: String
}


// MARK: - Mint Selection View
struct MintSelectionView: View {
    @Binding var selectedMints: Set<String>
    let discoveredMints: [DiscoveredMint]
    let isDiscoveringMints: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Info card
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green.opacity(0.8))
                
                Text("Mints are custodial services that issue ecash tokens. Select multiple mints to spread risk.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Mint list
            if isDiscoveringMints && discoveredMints.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle(tint: .green))
                    
                    Text("Discovering mints...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .frame(maxHeight: 300)
                .frame(maxWidth: .infinity)
            } else if discoveredMints.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text("No mints discovered")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                    
                    Text("Check your internet connection and try again")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: 300)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(discoveredMints, id: \.url) { mint in
                            MintRowView(
                                mint: mint,
                                isSelected: selectedMints.contains(mint.url),
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedMints.contains(mint.url) {
                                            selectedMints.remove(mint.url)
                                        } else {
                                            selectedMints.insert(mint.url)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            
            // Selected count
            if !selectedMints.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    
                    Text("\(selectedMints.count) mint\(selectedMints.count == 1 ? "" : "s") selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                    
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Mint Row View
struct MintRowView: View {
    let mint: DiscoveredMint
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.green : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                    }
                }
                
                // Mint icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.green.opacity(0.2),
                                    Color.green.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "building.columns")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                }
                
                // Mint info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mint.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let description = mint.description {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(2)
                    } else if !mint.recommendedBy.isEmpty {
                        Text("Recommended by \(mint.recommendedBy.count) user\(mint.recommendedBy.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Text(mint.url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.green.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct WalletOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        WalletOnboardingView()
            .environment(WalletManager(
                nostrManager: NostrManager(from: "Preview"),
                modelContext: try! ModelContainer(for: Transaction.self).mainContext,
                appState: AppState()
            ))
            .environment(NostrManager(from: "Preview"))
    }
}