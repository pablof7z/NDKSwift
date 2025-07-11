import SwiftUI
import NDKSwift

struct SendNutzapView: View {
    @ObservedObject var walletViewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var recipientPubkey = ""
    @State private var amount = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage = ""
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Recipient") {
                    TextField("npub or hex pubkey", text: $recipientPubkey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section("Amount") {
                    HStack {
                        TextField("0", text: $amount)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("sats")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Available: \(formatSats(walletViewModel.balance)) sats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Message (Optional)") {
                    TextField("Add a message...", text: $message)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                if isSending {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Sending nutzap...")
                        }
                    }
                } else {
                    Section {
                        Button("Send Nutzap") {
                            sendNutzap()
                        }
                        .disabled(!isValidInput())
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Send Nutzap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func isValidInput() -> Bool {
        guard !recipientPubkey.isEmpty,
              let amountValue = Int64(amount),
              amountValue > 0,
              amountValue <= walletViewModel.balance else {
            return false
        }
        
        // Basic validation for pubkey format
        let cleanPubkey = recipientPubkey.hasPrefix("npub") ? recipientPubkey : recipientPubkey
        return cleanPubkey.count >= 8 // Minimum reasonable length
    }
    
    private func sendNutzap() {
        guard let amountValue = Int64(amount) else { return }
        
        isSending = true
        errorMessage = ""
        
        Task {
            do {
                // Convert npub to hex if needed
                var targetPubkey = recipientPubkey
                if recipientPubkey.hasPrefix("npub") {
                    // In a real app, you'd decode the npub to hex
                    // For demo purposes, we'll use the input as-is
                    targetPubkey = recipientPubkey
                }
                
                try await walletViewModel.sendNutzap(
                    to: targetPubkey,
                    amount: amountValue,
                    message: message
                )
                
                await MainActor.run {
                    isSending = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}

#Preview {
    SendNutzapView(walletViewModel: WalletViewModel())
}
