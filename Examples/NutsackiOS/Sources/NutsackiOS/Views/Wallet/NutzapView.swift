import SwiftUI
import SwiftData
import NDKSwift

enum PaymentMethod {
    case nutzap
    case lightning
}

struct NutzapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    
    let recipientPubkey: String?
    
    @State private var resolvedUser: NDKUser?
    @State private var recipientProfile: NDKUserProfile?
    @State private var amount = ""
    @State private var comment = ""
    @State private var isLoadingProfile = false
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var acceptedMints: [String] = []
    @State private var availableBalance: Int = 0
    @State private var profileTask: Task<Void, Never>?
    @State private var supportsLightning = false
    @State private var paymentMethod: PaymentMethod = .nutzap
    @FocusState private var amountFieldFocused: Bool
    
    init(recipientPubkey: String? = nil) {
        self.recipientPubkey = recipientPubkey
    }
    
    var amountInt: Int {
        Int(amount) ?? 0
    }
    
    private var formattedAmount: String {
        if amount.isEmpty {
            return "0"
        }
        
        // Format with thousand separators
        if let number = Int(amount) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: number)) ?? amount
        }
        return amount
    }
    
    private func setAmount(_ preset: Int) {
        amount = "\(preset)"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Recipient Section - Centered display
                    if let user = resolvedUser {
                        VStack(spacing: 16) {
                            // Profile picture centered on top
                            UserProfilePicture(user: user, size: 80)
                            
                            VStack(spacing: 4) {
                                // User name centered below avatar
                                UserDisplayName(user: user)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                
                                // NIP-05 or identifier below name
                                UserNIP05(user: user)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else if isLoadingProfile {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading profile...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                        
                        // Amount Section
                        VStack(spacing: 16) {
                            // Hidden text field that drives the amount
                            TextField("0", text: $amount)
                                .keyboardType(.numberPad)
                                .opacity(0)
                                .frame(height: 0)
                                .focused($amountFieldFocused)
                            
                            // Visual amount display
                            VStack(spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(formattedAmount)
                                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    
                                    Text("sats")
                                        .font(.system(size: 20, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    amountFieldFocused = true
                                }
                                
                                // USD equivalent (placeholder)
                                Text("≈ $0.00 USD")
                                    .font(.system(size: 16, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .opacity(0.6)
                            }
                            
                            // Quick amount buttons
                            HStack(spacing: 12) {
                                ForEach([1000, 5000, 10000, 50000], id: \.self) { preset in
                                    Button(action: { setAmount(preset) }) {
                                        Text("\(preset / 1000)k")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.15))
                                            .cornerRadius(16)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                    // Comment Section
                    if resolvedUser != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Comment")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            TextField("Comment (optional)", text: $comment, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Payment method indicator
                    if resolvedUser != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                if paymentMethod == .nutzap {
                                    Image(systemName: "bitcoinsign.square.fill")
                                        .foregroundColor(.orange)
                                    Text("Nutzap")
                                        .font(.headline)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(.yellow)
                                    Text("Lightning Zap")
                                        .font(.headline)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            if paymentMethod == .nutzap && !acceptedMints.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(acceptedMints, id: \.self) { mint in
                                        Text(URL(string: mint)?.host ?? mint)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 100) // Add space for the fixed button
            }
            
            // Send Nutzap Button - Fixed at bottom
            VStack {
                Divider()
                
                Button(action: sendPayment) {
                    if isSending {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Sending...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.3))
                        .foregroundColor(.orange)
                        .cornerRadius(12)
                    } else {
                        HStack {
                            if paymentMethod == .nutzap {
                                Image(systemName: "bitcoinsign.square.fill")
                                Text("Send Nutzap")
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Send Lightning Zap")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                        .padding()
                        .background(paymentMethod == .nutzap ? Color.orange : Color.yellow)
                        .foregroundColor(paymentMethod == .nutzap ? .white : .black)
                        .cornerRadius(12)
                    }
                }
                .disabled(resolvedUser == nil || amount.isEmpty || amountInt <= 0 || (paymentMethod == .nutzap && amountInt > availableBalance) || isSending || (!supportsLightning && acceptedMints.isEmpty))
                .padding()
            }
            .background(Color(.systemBackground))
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(paymentMethod == .nutzap ? "Nutzap" : "Lightning Zap")
        .platformNavigationBarTitleDisplayMode(inline: true)
        #if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundColor(.orange)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showSuccess) {
            NutzapSuccessView(
                user: resolvedUser!,
                amount: amountInt
            ) {
                dismiss()
            }
        }
        .onAppear {
            loadBalance()
            
            // If a recipient pubkey was provided, resolve it
            if let pubkey = recipientPubkey {
                Task {
                    await resolveRecipient(pubkey: pubkey)
                }
            }
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
    
    private func resolveRecipient(pubkey: String) async {
        guard !pubkey.isEmpty else {
            await MainActor.run {
                resolvedUser = nil
                recipientProfile = nil
            }
            return
        }
        
        await MainActor.run {
            isLoadingProfile = true
        }
        
        profileTask?.cancel()
        
        do {
            guard let ndk = nostrManager.ndk else {
                throw NostrError.ndkNotInitialized
            }
            
            let user = NDKUser(pubkey: pubkey)
            
            await MainActor.run {
                resolvedUser = user
                isLoadingProfile = false
            }
            
            // Observe profile updates
            profileTask = Task {
                let profileStream = await ndk.observeProfile(for: pubkey, closeOnEose: true)
                
                for await profile in profileStream {
                    await MainActor.run {
                        self.recipientProfile = profile
                    }
                    // For nutzap, we can close after first profile
                    if profile != nil {
                        break
                    }
                }
            }
            
            // Load accepted mints and check Lightning support
            await loadAcceptedMints(for: pubkey)
            await checkLightningSupport(for: pubkey)
        } catch {
            await MainActor.run {
                resolvedUser = nil
                recipientProfile = nil
                isLoadingProfile = false
            }
        }
    }
    
    private func sendPayment() {
        guard let recipient = resolvedUser,
              amountInt > 0 else { return }
        
        let recipientPubkey = recipient.pubkey
        
        isSending = true
        
        Task {
            do {
                if paymentMethod == .nutzap && !acceptedMints.isEmpty {
                    // Convert accepted mints to URLs
                    let mintURLs = acceptedMints.compactMap { URL(string: $0) }
                    
                    try await walletManager.sendNutzap(
                        to: recipientPubkey,
                        amount: Int64(amountInt),
                        comment: comment.isEmpty ? nil : comment,
                        acceptedMints: mintURLs
                    )
                } else if supportsLightning {
                    // Send Lightning zap (either chosen or fallback)
                    guard let ndk = nostrManager.ndk,
                          let zapManager = nostrManager.zapManager else {
                        throw ZapError.zapManagerNotAvailable
                    }
                    
                    let user = NDKUser(pubkey: recipientPubkey)
                    user.ndk = ndk
                    
                    _ = try await zapManager.zap(
                        to: user,
                        amountSats: Int64(amountInt),
                        comment: comment.isEmpty ? nil : comment
                    )
                } else {
                    // No payment method available
                    throw ZapError.zapManagerNotAvailable
                }
                
                // Transaction will be recorded automatically
                await MainActor.run {
                    showSuccess = true
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSending = false
                }
            }
        }
    }
    
    private func loadAcceptedMints(for pubkey: String) async {
        guard let ndk = nostrManager.ndk else { return }
        
        do {
            // Fetch nutzap preferences event (kind 10019) - NIP-61
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.nutzapPreferences],
                limit: 1
            )
            
            let events = try await ndk.fetchEvents([filter])
            guard let preferencesEvent = events.first else {
                // If recipient has no nutzap preferences, they can't receive nutzaps
                await MainActor.run {
                    acceptedMints = []
                }
                return
            }
            
            // Parse mints from event tags
            var mints: [String] = []
            for tag in preferencesEvent.tags where tag.count >= 2 && tag[0] == "mint" {
                mints.append(tag[1])
            }
            
            // Don't add fallback mints - recipient must have configured mints
            
            await MainActor.run {
                acceptedMints = mints
                // Determine payment method: prefer nutzap if mints available, otherwise lightning
                if !mints.isEmpty {
                    paymentMethod = .nutzap
                } else if supportsLightning {
                    paymentMethod = .lightning
                } else {
                    paymentMethod = .nutzap // Will show error when trying to send
                }
            }
        } catch {
            print("Failed to load accepted mints: \(error)")
            await MainActor.run {
                acceptedMints = []
                // If no mints and lightning is available, use lightning
                if supportsLightning {
                    paymentMethod = .lightning
                } else {
                    paymentMethod = .nutzap
                }
            }
        }
    }
    
    private func loadBalance() {
        Task {
            do {
                let balance = try await walletManager.activeWallet?.getBalance() ?? 0
                await MainActor.run {
                    availableBalance = Int(balance)
                }
            } catch {
                print("Failed to get balance: \(error)")
            }
        }
    }
    
    private func checkLightningSupport(for pubkey: String) async {
        guard let ndk = nostrManager.ndk else { return }
        
        do {
            let profile = try await ndk.fetchProfile(for: pubkey)
            await MainActor.run {
                supportsLightning = profile?.lud16 != nil || profile?.lud06 != nil
            }
        } catch {
            print("Failed to check Lightning support: \(error)")
            await MainActor.run {
                supportsLightning = false
            }
        }
    }
}

// MARK: - Errors
enum ZapError: LocalizedError {
    case zapManagerNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .zapManagerNotAvailable:
            return "Zap manager is not available."
        }
    }
}

// MARK: - Nutzap Success View
struct NutzapSuccessView: View {
    let user: NDKUser
    let amount: Int
    let onDone: () -> Void
    
    @State private var animationScale = 0.5
    @State private var showBolt = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Animation
            ZStack {
                // Profile picture
                UserProfilePicture(user: user, size: 100)
                
                // Bolt overlay
                if showBolt {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)
                        .scaleEffect(animationScale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            VStack(spacing: 8) {
                Text("Nutzapped!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                HStack(spacing: 4) {
                    Text("\(amount) sats to")
                    UserDisplayName(user: user)
                }
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                showBolt = true
            }
            
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                animationScale = 1.2
            }
        }
    }
}