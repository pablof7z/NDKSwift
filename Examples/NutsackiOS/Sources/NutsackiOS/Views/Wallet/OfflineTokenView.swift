import SwiftUI
import CashuSwift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OfflineTokenView: View {
    let token: String
    let amount: Int
    let memo: String
    let mintURL: URL?
    
    @State private var copied = false
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // QR Code
                    VStack(spacing: 20) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            
                            QRCodeView(content: token)
                                .padding(20)
                        }
                        .frame(width: 280, height: 280)
                        
                        Text("Scan to receive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Success header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.green)
                        }
                    }
                    
                    // Amount display
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(formatAmount(amount))
                                .font(.system(size: 48, weight: .semibold, design: .rounded))
                            Text("sats")
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        
                        if !memo.isEmpty {
                            Text(memo)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        if let mint = mintURL?.host {
                            Label(mint, systemImage: "building.columns.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    // Token preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Token")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if copied {
                                Label("Copied", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        
                        Text(token)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .onTapGesture {
                                copyToken()
                            }
                    }
                    .padding(.horizontal)
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        Button(action: shareToken) {
                            Label("Share Token", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        Button(action: copyToken) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .padding(.horizontal)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Label("This token works offline", systemImage: "wifi.slash")
                        Label("Share via QR code or text", systemImage: "qrcode")
                        Label("Recipient can claim when online", systemImage: "arrow.down.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Offline Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [token])
        }
        #endif
    }
    
    private func formatAmount(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }
    
    private func copyToken() {
        #if os(iOS)
        UIPasteboard.general.string = token
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
        showShareSheet = true
        #else
        copyToken() // On macOS, just copy instead
        #endif
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// Helper struct for proof information
struct ProofInfo: Identifiable {
    let id: String
    let amount: Int64
    let keysetId: String
    let proof: CashuSwift.Proof?
}

