import SwiftUI
import NDKSwift

struct SendView: View {
    @ObservedObject var walletManager: OlasWalletManager
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) var dismiss
    
    @State private var recipient = ""
    @State private var amount = ""
    @State private var comment = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showingSuccess = false
    @State private var recipientProfile: NDKUserProfile?
    @State private var searchResults: [NDKUser] = []
    @State private var isSearching = false
    
    let presetAmounts = [100, 500, 1000, 5000, 10000, 50000]
    
    var body: some View {
        NavigationView {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Header
                        VStack(spacing: OlasDesign.Spacing.md) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                        .rotationEffect(.degrees(-45))
                                )
                            
                            Text("Send Sats")
                                .font(OlasDesign.Typography.title)
                                .foregroundStyle(OlasDesign.Colors.text)
                        }
                        .padding(.top, OlasDesign.Spacing.lg)
                        
                        // Recipient input
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                            Text("Recipient")
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                            
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.title2)
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                                
                                TextField("Username or pubkey", text: $recipient)
                                    .font(OlasDesign.Typography.body)
                                    .foregroundStyle(OlasDesign.Colors.text)
                                    .onChange(of: recipient) { _, newValue in
                                        searchRecipient(newValue)
                                    }
                            }
                            .padding(OlasDesign.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                    .fill(OlasDesign.Colors.surface)
                            )
                            
                            // Search results
                            if !searchResults.isEmpty {
                                VStack(spacing: OlasDesign.Spacing.xs) {
                                    ForEach(searchResults, id: \.pubkey) { user in
                                        Button {
                                            selectRecipient(user)
                                        } label: {
                                            HStack(spacing: OlasDesign.Spacing.sm) {
                                                OlasAvatar(
                                                    url: recipientProfile?.picture,
                                                    size: 32,
                                                    pubkey: user.pubkey
                                                )
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(recipientProfile?.displayName ?? recipientProfile?.name ?? "User")
                                                        .font(OlasDesign.Typography.bodyMedium)
                                                        .foregroundStyle(OlasDesign.Colors.text)
                                                    
                                                    Text("@\(recipientProfile?.name ?? user.pubkey.prefix(8))")
                                                        .font(OlasDesign.Typography.caption)
                                                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                                                }
                                                
                                                Spacer()
                                            }
                                            .padding(OlasDesign.Spacing.sm)
                                        }
                                    }
                                }
                                .padding(OlasDesign.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                        .fill(OlasDesign.Colors.surface)
                                )
                            }
                            
                            // Selected recipient display
                            if let profile = recipientProfile {
                                HStack(spacing: OlasDesign.Spacing.sm) {
                                    OlasAvatar(
                                        url: profile.picture,
                                        size: 40,
                                        pubkey: recipient
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName ?? profile.name ?? "User")
                                            .font(OlasDesign.Typography.bodyMedium)
                                            .foregroundStyle(OlasDesign.Colors.text)
                                        
                                        if profile.lud16 != nil || profile.lud06 != nil {
                                            Label("Lightning enabled", systemImage: "checkmark.circle.fill")
                                                .font(OlasDesign.Typography.caption)
                                                .foregroundStyle(OlasDesign.Colors.success)
                                        } else {
                                            Label("No Lightning address", systemImage: "exclamationmark.triangle.fill")
                                                .font(OlasDesign.Typography.caption)
                                                .foregroundStyle(OlasDesign.Colors.warning)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(OlasDesign.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                        .fill(OlasDesign.Colors.surface.opacity(0.5))
                                )
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Amount selection
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                            Text("Amount")
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                            
                            // Preset amounts
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: OlasDesign.Spacing.sm) {
                                ForEach(presetAmounts, id: \.self) { preset in
                                    Button {
                                        amount = "\(preset)"
                                        OlasDesign.Haptic.selection()
                                    } label: {
                                        Text(formatAmount(preset))
                                            .font(OlasDesign.Typography.bodyMedium)
                                            .foregroundStyle(amount == "\(preset)" ? .white : OlasDesign.Colors.text)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, OlasDesign.Spacing.sm)
                                            .background(
                                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                                                    .fill(amount == "\(preset)" ? OlasDesign.accentGradient : Color(OlasDesign.Colors.surface))
                                            )
                                    }
                                }
                            }
                            
                            // Custom amount
                            HStack {
                                Image(systemName: "bitcoinsign.circle")
                                    .font(.title2)
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                                
                                TextField("Custom amount", text: $amount)
                                    .font(OlasDesign.Typography.body)
                                    .foregroundStyle(OlasDesign.Colors.text)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                
                                Text("sats")
                                    .font(OlasDesign.Typography.body)
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                            }
                            .padding(OlasDesign.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                    .fill(OlasDesign.Colors.surface)
                            )
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Comment
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                            Text("Comment (optional)")
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                            
                            HStack {
                                Image(systemName: "text.bubble")
                                    .font(.title2)
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                                
                                TextField("Add a message", text: $comment)
                                    .font(OlasDesign.Typography.body)
                                    .foregroundStyle(OlasDesign.Colors.text)
                            }
                            .padding(OlasDesign.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                    .fill(OlasDesign.Colors.surface)
                            )
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.error)
                                .padding(.horizontal, OlasDesign.Spacing.md)
                        }
                        
                        // Send button
                        OlasButton(
                            title: "Send",
                            action: {
                                Task {
                                    await sendSats()
                                }
                            },
                            style: .primary,
                            isLoading: isSending,
                            isDisabled: recipient.isEmpty || amount.isEmpty
                        )
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Send")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .automatic) {
                #endif
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(OlasDesign.Colors.text)
                }
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Payment sent successfully!")
            }
        }
    }
    
    private func formatAmount(_ sats: Int) -> String {
        if sats >= 1000 {
            return "\(sats / 1000)k"
        }
        return "\(sats)"
    }
    
    private func searchRecipient(_ query: String) {
        guard !query.isEmpty, nostrManager.ndk != nil else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            // Search for users by name
            // In a real implementation, this would search properly
            searchResults = []
            isSearching = false
        }
    }
    
    private func selectRecipient(_ user: NDKUser) {
        recipient = user.pubkey
        searchResults = []
        
        Task {
            // Load profile
            if let profileManager = nostrManager.ndk?.profileManager {
                for await profile in await profileManager.observe(for: user.pubkey, maxAge: 3600) {
                    await MainActor.run {
                        recipientProfile = profile
                    }
                    break
                }
            }
        }
    }
    
    private func sendSats() async {
        guard let satsAmount = Int64(amount) else {
            errorMessage = "Invalid amount"
            return
        }
        
        guard satsAmount > 0 else {
            errorMessage = "Amount must be greater than 0"
            return
        }
        
        guard satsAmount <= walletManager.currentBalance else {
            errorMessage = "Insufficient balance"
            OlasDesign.Haptic.error()
            return
        }
        
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        
        do {
            try await walletManager.sendSats(
                to: recipient,
                amount: satsAmount,
                comment: comment.isEmpty ? nil : comment
            )
            
            OlasDesign.Haptic.success()
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            OlasDesign.Haptic.error()
        }
    }
}