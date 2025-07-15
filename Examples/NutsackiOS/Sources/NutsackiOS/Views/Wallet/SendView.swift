import SwiftUI
import SwiftData
import NDKSwift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(WalletManager.self) private var walletManager
    
    @State private var amount = ""
    @State private var memo = ""
    @State private var selectedMintURL: URL?
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatedToken: String?
    @State private var showTokenView = false
    
    @State private var availableBalance: Int = 0
    @State private var mints: [MintInfo] = []
    
    var availableBalanceForMint: Int {
        return availableBalance
    }
    
    var amountInt: Int {
        Int(amount) ?? 0
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Amount", text: $amount)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text("sats")
                        .foregroundStyle(.secondary)
                }
                
                if !mints.isEmpty {
                    Picker("From Mint", selection: $selectedMintURL) {
                        Text("Auto-select").tag(nil as URL?)
                        ForEach(mints, id: \.url.absoluteString) { mint in
                            Text(mint.url.host ?? mint.url.absoluteString).tag(mint.url as URL?)
                        }
                    }
                }
                
                HStack {
                    Text("Available:")
                    Spacer()
                    Text("\(availableBalanceForMint) sats")
                        .foregroundStyle(amountInt > availableBalanceForMint ? .red : .secondary)
                }
            } header: {
                Text("Amount")
            }
            
            Section {
                TextField("Note (optional)", text: $memo, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Memo")
            } footer: {
                Text("Add a note for the recipient")
            }
            
            Section {
                Button(action: generateToken) {
                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Generate Token")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(amount.isEmpty || amountInt <= 0 || amountInt > availableBalanceForMint || isSending)
            }
        }
        .navigationTitle("Send Ecash")
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
        .sheet(isPresented: $showTokenView) {
            if let token = generatedToken {
                TokenView(token: token, amount: amountInt, memo: memo)
            }
        }
        .onAppear {
            loadMints()
            updateAvailableBalance()
        }
        .onChange(of: selectedMintURL) { _, _ in
            updateAvailableBalance()
        }
    }
    
    private func generateToken() {
        guard amountInt > 0 else { return }
        
        isSending = true
        
        Task {
            do {
                // Generate ecash token
                let tokenString = try await walletManager.send(
                    amount: Int64(amountInt),
                    memo: memo.isEmpty ? nil : memo,
                    fromMint: selectedMintURL
                )
                
                // Transaction will be recorded automatically via NIP-60 history events
                await MainActor.run {
                    generatedToken = tokenString
                    showTokenView = true
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
    
    private func updateAvailableBalance() {
        Task {
            if let mintURL = selectedMintURL {
                let balance = await walletManager.getBalance(for: mintURL)
                await MainActor.run {
                    availableBalance = Int(balance)
                }
            } else {
                // Get total balance
                do {
                    let totalBalance = try await walletManager.getBalance()
                    await MainActor.run {
                        availableBalance = Int(totalBalance)
                    }
                } catch {
                    print("Failed to get balance: \(error)")
                }
            }
        }
    }
    
    private func loadMints() {
        Task {
            let loadedMints = await walletManager.getMintsInfo()
            await MainActor.run {
                mints = loadedMints
                selectedMintURL = mints.first?.url
            }
        }
    }
}

// MARK: - Token View
struct TokenView: View {
    let token: String
    let amount: Int
    let memo: String
    
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Success indicator
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                        .padding(.top, 40)
                    
                    // Amount
                    VStack(spacing: 8) {
                        Text("\(amount) sats")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if !memo.isEmpty {
                            Text(memo)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    // QR Code
                    QRCodeView(content: token)
                    
                    // Token text
                    VStack(spacing: 12) {
                        Text(token)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)
                        
                        Button(action: copyToken) {
                            Label(
                                copied ? "Copied!" : "Copy Token",
                                systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(copied ? .green : .orange)
                        
                        Button(action: shareToken) {
                            Label("Share Token", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Ecash Token")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func copyToken() {
        #if os(iOS)
        UIPasteboard.general.string = token
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        #endif
        withAnimation {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
    
    private func shareToken() {
        #if os(iOS)
        let activityController = UIActivityViewController(
            activityItems: [token],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
        #else
        // On macOS, copy to clipboard instead
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        #endif
    }
    
}