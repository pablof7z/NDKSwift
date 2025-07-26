import SwiftUI
import NDKSwift

struct NutZapView: View {
    @ObservedObject var walletManager: OlasWalletManager
    let nostrManager: NostrManager
    let recipientPubkey: String?
    
    @State private var selectedAmount: Int64 = 21
    @State private var customAmount: String = ""
    @State private var comment: String = ""
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var selectedUser: NDKUserProfile?
    @State private var selectedUserPubkey: String?
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    private let quickAmounts: [Int64] = [21, 100, 500, 1000, 5000, 10000]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        OlasDesign.Colors.background,
                        OlasDesign.Colors.surface.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Header with balance
                        VStack(spacing: OlasDesign.Spacing.sm) {
                            Text("⚡ NutZap")
                                .font(OlasDesign.Typography.title)
                                .foregroundStyle(OlasDesign.Colors.text)
                            
                            Text("Send ecash instantly")
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                            
                            HStack(spacing: 4) {
                                Text("Balance:")
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundStyle(OlasDesign.Colors.textTertiary)
                                
                                Text("\(walletManager.currentBalance) sats")
                                    .font(OlasDesign.Typography.captionMedium)
                                    .foregroundStyle(OlasDesign.Colors.primary)
                            }
                        }
                        .padding(.top, OlasDesign.Spacing.md)
                        
                        // Recipient selector
                        if recipientPubkey == nil {
                            recipientSelector
                        } else if let userProfile = selectedUser {
                            selectedRecipientCard(profile: userProfile, pubkey: recipientPubkey!)
                        }
                        
                        // Amount selection
                        amountSection
                        
                        // Comment field
                        commentField
                        
                        // Send button
                        sendButton
                    }
                    .padding(.horizontal, OlasDesign.Spacing.lg)
                    .padding(.bottom, OlasDesign.Spacing.xl)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(OlasDesign.Colors.primary)
                }
            }
            .task {
                if let pubkey = recipientPubkey {
                    await loadUserProfile(pubkey: pubkey)
                }
            }
            .alert("Success!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("NutZap sent successfully!")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private var recipientSelector: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            Text("Recipient")
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundStyle(OlasDesign.Colors.text)
            
            HStack(spacing: OlasDesign.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(OlasDesign.Colors.textTertiary)
                
                TextField("Search by name or npub...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await searchUser()
                        }
                    }
            }
            .padding(OlasDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(OlasDesign.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .stroke(OlasDesign.Colors.divider, lineWidth: 1)
            )
            
            if isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                }
                .padding(.top, OlasDesign.Spacing.xs)
            }
        }
    }
    
    private func selectedRecipientCard(profile: NDKUserProfile, pubkey: String) -> some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Avatar
            if let avatarURL = profile.image {
                AsyncImage(url: URL(string: avatarURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(OlasDesign.Colors.surface)
                        .overlay(
                            Text((profile.displayName ?? profile.name ?? "?").prefix(1))
                                .font(OlasDesign.Typography.bodyMedium)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? profile.name ?? "Anonymous")
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(OlasDesign.Colors.text)
                
                Text("@\(profile.name ?? String(pubkey.prefix(8)))")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
            
            Spacer()
            
            if recipientPubkey == nil {
                Button {
                    selectedUser = nil
                    selectedUserPubkey = nil
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                }
            }
        }
        .padding(OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .stroke(OlasDesign.Colors.primary.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Amount")
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundStyle(OlasDesign.Colors.text)
            
            // Quick amount buttons
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: OlasDesign.Spacing.sm) {
                ForEach(quickAmounts, id: \.self) { amount in
                    Button {
                        selectedAmount = amount
                        customAmount = ""
                        OlasDesign.Haptic.selection()
                    } label: {
                        Text("\(amount)")
                            .font(OlasDesign.Typography.bodyMedium)
                            .foregroundStyle(selectedAmount == amount ? .white : OlasDesign.Colors.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OlasDesign.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                                    .fill(selectedAmount == amount ? OlasDesign.Colors.primary : OlasDesign.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                                    .stroke(selectedAmount == amount ? Color.clear : OlasDesign.Colors.divider, lineWidth: 1)
                            )
                    }
                }
            }
            
            // Custom amount
            HStack {
                TextField("Custom amount", text: $customAmount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .onChange(of: customAmount) { _, newValue in
                        if !newValue.isEmpty {
                            selectedAmount = Int64(newValue) ?? 0
                        }
                    }
                
                Text("sats")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
            .padding(OlasDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(OlasDesign.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .stroke(customAmount.isEmpty ? OlasDesign.Colors.divider : OlasDesign.Colors.primary, lineWidth: 1)
            )
        }
    }
    
    private var commentField: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            Text("Comment (optional)")
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundStyle(OlasDesign.Colors.text)
            
            TextField("Add a message...", text: $comment, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...5)
                .padding(OlasDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .stroke(OlasDesign.Colors.divider, lineWidth: 1)
                )
        }
    }
    
    private var sendButton: some View {
        Button {
            Task {
                await sendNutZap()
            }
        } label: {
            HStack(spacing: OlasDesign.Spacing.sm) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "bolt.heart.fill")
                }
                
                Text(isSending ? "Sending..." : "Send NutZap")
            }
            .font(OlasDesign.Typography.bodyMedium)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OlasDesign.Spacing.md)
            .background(
                LinearGradient(
                    colors: OlasDesign.Colors.primaryGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(OlasDesign.CornerRadius.full)
            .shadow(color: OlasDesign.Colors.primary.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .disabled(isSending || selectedAmount == 0 || (recipientPubkey == nil && selectedUserPubkey == nil))
        .opacity((selectedAmount == 0 || (recipientPubkey == nil && selectedUserPubkey == nil)) ? 0.5 : 1)
    }
    
    private func loadUserProfile(pubkey: String) async {
        guard let ndk = nostrManager.ndk else { return }
        
        do {
            if let profile = try await ndk.fetchProfile(pubkey: pubkey) {
                await MainActor.run {
                    self.selectedUser = profile
                    self.selectedUserPubkey = pubkey
                }
            }
        } catch {
            print("Failed to load profile: \(error)")
        }
    }
    
    private func searchUser() async {
        guard !searchQuery.isEmpty else { return }
        
        await MainActor.run {
            isSearching = true
        }
        
        defer {
            Task { @MainActor in
                isSearching = false
            }
        }
        
        // Try to decode npub
        if searchQuery.starts(with: "npub1") {
            do {
                let pubkey = try NDKUser.pubkeyFromNpub(searchQuery)
                await loadUserProfile(pubkey: pubkey)
                return
            } catch {
                print("Invalid npub: \(error)")
            }
        }
        
        // Search by name - for now just show error
        await MainActor.run {
            errorMessage = "Search by name coming soon. Please use npub for now."
        }
    }
    
    private func sendNutZap() async {
        let targetPubkey = recipientPubkey ?? selectedUserPubkey
        guard let pubkey = targetPubkey else { return }
        
        await MainActor.run {
            isSending = true
        }
        
        defer {
            Task { @MainActor in
                isSending = false
            }
        }
        
        do {
            // Find a recent event from the user to zap
            guard let ndk = nostrManager.ndk else { return }
            
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.textNote],
                limit: 1
            )
            
            if let event = try await ndk.fetchEvent(filter: filter) {
                try await walletManager.zapEvent(event, amount: selectedAmount, comment: comment.isEmpty ? nil : comment)
                
                await MainActor.run {
                    showSuccess = true
                    OlasDesign.Haptic.success()
                }
            } else {
                await MainActor.run {
                    errorMessage = "Couldn't find a recent post from this user to zap"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                OlasDesign.Haptic.error()
            }
        }
    }
}