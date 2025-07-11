import SwiftUI
import NDKSwift

struct ReceiveNutzapView: View {
    @ObservedObject var walletViewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var amount = ""
    @State private var receiveToken = ""
    @State private var isGenerating = false
    @State private var showingQR = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Request Amount") {
                    HStack {
                        TextField("0", text: $amount)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("sats")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Create a receive token for a specific amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isGenerating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Generating receive token...")
                        }
                    }
                } else if !receiveToken.isEmpty {
                    Section("Receive Token") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Share this token to receive payment:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(receiveToken)
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                            
                            HStack {
                                Button("Copy Token") {
                                    copyToClipboard(receiveToken)
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Show QR") {
                                    showingQR = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    Section {
                        Button("Generate Receive Token") {
                            generateReceiveToken()
                        }
                        .disabled(amount.isEmpty || Int64(amount) == nil || Int64(amount) ?? 0 <= 0)
                        .frame(maxWidth: .infinity)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to receive:")
                            .font(.headline)
                        
                        Text("1. Enter the amount you want to receive")
                            .font(.caption)
                        Text("2. Generate a receive token")
                            .font(.caption)
                        Text("3. Share the token with the sender")
                            .font(.caption)
                        Text("4. They can redeem it to send you sats")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Receive Nutzap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingQR) {
                QRCodeView(text: receiveToken)
            }
        }
    }
    
    private func generateReceiveToken() {
        guard let amountValue = Int64(amount) else { return }
        
        isGenerating = true
        
        Task {
            do {
                let token = try await walletViewModel.createReceiveToken(amount: amountValue)
                
                await MainActor.run {
                    receiveToken = token
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    // Could show error alert here
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

struct QRCodeView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Scan QR Code")
                    .font(.headline)
                
                // In a real app, you'd generate an actual QR code here
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 200)
                    .cornerRadius(12)
                    .overlay(
                        VStack {
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("QR Code")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                
                Text("QR code generation would be implemented here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Copy Token Instead") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = text
                    #elseif canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #endif
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ReceiveNutzapView(walletViewModel: WalletViewModel())
}
