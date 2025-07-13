import SwiftUI
import SwiftData
import NDKSwift

struct NutzapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var recipientInput = ""
    @State private var resolvedUser: NDKUser?
    @State private var amount = ""
    @State private var comment = ""
    @State private var isResolving = false
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var acceptedMints: [String] = []
    @State private var showQRScanner = false
    @State private var availableBalance: Int = 0
    
    var amountInt: Int {
        Int(amount) ?? 0
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("npub, NIP-05, or hex pubkey", text: $recipientInput)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        
                        #if os(iOS)
                        Button(action: { showQRScanner = true }) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.orange)
                        }
                        #endif
                    }
                    
                    if isResolving {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Resolving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let user = resolvedUser {
                        HStack {
                            // Profile picture
                            UserProfilePicture(user: user)
                            
                            VStack(alignment: .leading) {
                                UserDisplayName(user: user)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                UserNIP05(user: user)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Recipient")
            }
            
            Section {
                HStack {
                    TextField("Amount", text: $amount)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text("sats")
                        .foregroundStyle(.secondary)
                }
                
                if !acceptedMints.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accepted mints:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(acceptedMints, id: \.self) { mint in
                            Text(URL(string: mint)?.host ?? mint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Amount")
            }
            
            Section {
                TextField("Comment (optional)", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Comment")
            } footer: {
                Text("Your comment will be public on Nostr")
            }
            
            Section {
                Button(action: sendNutzap) {
                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Send Nutzap")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(resolvedUser == nil || amount.isEmpty || amountInt <= 0 || amountInt > availableBalance || isSending)
            }
        }
        .navigationTitle("Nutzap")
        .platformNavigationBarTitleDisplayMode(inline: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
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
        .onChange(of: recipientInput) { _, _ in
            resolveRecipient()
        }
        .onAppear {
            loadBalance()
        }
        #if os(iOS)
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { scannedCode in
                recipientInput = scannedCode
                showQRScanner = false
            }
        }
        #endif
    }
    
    private func resolveRecipient() {
        guard !recipientInput.isEmpty else {
            resolvedUser = nil
            return
        }
        
        isResolving = true
        
        Task {
            do {
                guard let ndk = nostrManager.ndk else {
                    throw NostrError.ndkNotInitialized
                }
                
                var pubkey: String?
                
                // Try to parse as npub
                if recipientInput.starts(with: "npub1") {
                    pubkey = NostrIdentifier.hex(fromNpub: recipientInput)
                }
                // Try as hex pubkey
                else if recipientInput.count == 64 {
                    pubkey = recipientInput
                }
                // Try as NIP-05
                else if recipientInput.contains("@") {
                    pubkey = try await resolveNIP05(recipientInput)
                }
                
                if let pubkey = pubkey {
                    let user = NDKUser(pubkey: pubkey)
                    // Try to fetch profile
                    let metadataFilter = NDKFilter(
                        authors: [pubkey],
                        kinds: [0],
                        limit: 1
                    )
                    if let event = try? await ndk.fetchEvent(metadataFilter),
                       let contentData = event.content.data(using: .utf8),
                       let metadata = try? JSONDecoder().decode(NDKUserProfile.self, from: contentData) {
                        // Profile will be loaded via async property
                    }
                    
                    await MainActor.run {
                        resolvedUser = user
                        isResolving = false
                    }
                    
                    // Load accepted mints
                    await loadAcceptedMints(for: pubkey)
                } else {
                    await MainActor.run {
                        resolvedUser = nil
                        isResolving = false
                    }
                }
            } catch {
                await MainActor.run {
                    resolvedUser = nil
                    isResolving = false
                }
            }
        }
    }
    
    private func sendNutzap() {
        guard let recipient = resolvedUser,
              amountInt > 0 else { return }
        
        let recipientPubkey = recipient.pubkey
        
        isSending = true
        
        Task {
            do {
                // Convert accepted mints to URLs
                let mintURLs = acceptedMints.compactMap { URL(string: $0) }
                
                // Send nutzap
                // Don't send if no accepted mints
                guard !mintURLs.isEmpty else {
                    throw NutzapError.noAcceptedMints
                }
                
                try await walletManager.sendNutzap(
                    to: recipientPubkey,
                    amount: Int64(amountInt),
                    comment: comment.isEmpty ? nil : comment,
                    acceptedMints: mintURLs
                )
                
                // Create transaction record
                let transaction = Transaction(
                    type: .nutzap,
                    amount: amountInt,
                    memo: comment.isEmpty ? "Nutzap" : comment
                )
                transaction.status = .completed
                
                await MainActor.run {
                    modelContext.insert(transaction)
                    do {
                        try modelContext.save()
                    } catch {
                        print("Failed to save transaction: \(error)")
                    }
                    
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
            // Fetch NIP-60 wallet event (kind 37375)
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [37375],
                limit: 1
            )
            
            let events = try await ndk.fetchEvents(filter)
            guard let walletEvent = events.first else {
                // If recipient has no wallet, they can't receive nutzaps
                await MainActor.run {
                    acceptedMints = []
                }
                return
            }
            
            // Parse mints from event tags
            var mints: [String] = []
            for tag in walletEvent.tags where tag.count >= 2 && tag[0] == "mint" {
                mints.append(tag[1])
            }
            
            // Don't add fallback mints - recipient must have configured mints
            
            await MainActor.run {
                acceptedMints = mints
            }
        } catch {
            print("Failed to load accepted mints: \(error)")
            await MainActor.run {
                acceptedMints = []
            }
        }
    }
    
    private func resolveNIP05(_ identifier: String) async throws -> String? {
        // Parse NIP-05 identifier
        let parts = identifier.split(separator: "@")
        guard parts.count == 2 else {
            throw NutzapError.invalidRecipient
        }
        
        let name = String(parts[0])
        let domain = String(parts[1])
        
        // Construct well-known URL
        let urlString = "https://\(domain)/.well-known/nostr.json?name=\(name)"
        guard let url = URL(string: urlString) else {
            throw NutzapError.invalidRecipient
        }
        
        // Fetch NIP-05 data
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Parse response
        struct NIP05Response: Codable {
            let names: [String: String]
        }
        
        let response = try JSONDecoder().decode(NIP05Response.self, from: data)
        
        // Get pubkey for name
        guard let pubkey = response.names[name.lowercased()] else {
            throw NutzapError.invalidRecipient
        }
        
        return pubkey
    }
    
    private func loadBalance() {
        Task {
            do {
                let balance = try await walletManager.getBalance()
                await MainActor.run {
                    availableBalance = Int(balance)
                }
            } catch {
                print("Failed to get balance: \(error)")
            }
        }
    }
}

// MARK: - Errors
enum NutzapError: LocalizedError {
    case invalidRecipient
    case noAcceptedMints
    
    var errorDescription: String? {
        switch self {
        case .invalidRecipient:
            return "Invalid recipient. Please enter a valid npub or hex pubkey."
        case .noAcceptedMints:
            return "Recipient has no configured mints to receive nutzaps."
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