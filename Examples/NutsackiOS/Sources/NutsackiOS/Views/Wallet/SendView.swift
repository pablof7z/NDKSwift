import SwiftUI
import SwiftData
import NDKSwift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SendView: View {
    let wallet: CashuWallet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var amount = ""
    @State private var memo = ""
    @State private var selectedMint: Mint?
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatedToken: String?
    @State private var showTokenView = false
    
    @State private var availableBalance: Int = 0
    
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
                        .keyboardType(.numberPad)
                    Text("sats")
                        .foregroundStyle(.secondary)
                }
                
                if !wallet.mints.isEmpty {
                    Picker("From Mint", selection: $selectedMint) {
                        Text("Auto-select").tag(nil as Mint?)
                        ForEach(wallet.mints) { mint in
                            Text(mint.displayName).tag(mint as Mint?)
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
        .navigationBarTitleDisplayMode(.inline)
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
            selectedMint = wallet.mints.first
            updateAvailableBalance()
        }
        .onChange(of: selectedMint) { _, _ in
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
                    fromMint: selectedMint?.url
                )
                
                // Create transaction record
                let transaction = Transaction(
                    type: .send,
                    amount: amountInt,
                    memo: memo.isEmpty ? nil : memo
                )
                transaction.wallet = wallet
                transaction.status = .completed
                
                await MainActor.run {
                    modelContext.insert(transaction)
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("Failed to save transaction: \(error)")
                    }
                    
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
            if let mint = selectedMint {
                let balance = await walletManager.getBalance(for: mint.url)
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
                    logger.error("Failed to get balance: \(error)")
                }
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
                    if let qrImage = generateQRCode(from: token) {
                        #if os(iOS)
                        Image(uiImage: qrImage)
                        #else
                        Image(nsImage: qrImage)
                        #endif
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 250, height: 250)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    
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
            .navigationBarTitleDisplayMode(.inline)
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
    
    #if os(iOS)
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .utf8)
        
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            
            if let output = filter.outputImage?.transformed(by: transform) {
                let context = CIContext()
                if let cgImage = context.createCGImage(output, from: output.extent) {
                    return UIImage(cgImage: cgImage)
                }
            }
        }
        
        return nil
    }
    #else
    private func generateQRCode(from string: String) -> NSImage? {
        let data = string.data(using: .utf8)
        
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            
            if let output = filter.outputImage?.transformed(by: transform) {
                let rep = NSCIImageRep(ciImage: output)
                let nsImage = NSImage(size: rep.size)
                nsImage.addRepresentation(rep)
                return nsImage
            }
        }
        
        return nil
    }
    #endif
}