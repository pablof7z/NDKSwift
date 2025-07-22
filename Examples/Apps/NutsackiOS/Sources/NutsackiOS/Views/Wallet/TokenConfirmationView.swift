import SwiftUI
import CashuSwift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct TokenConfirmationView: View {
    let token: String?
    let amount: Int
    let memo: String
    let mintURL: URL?
    let isOfflineMode: Bool
    let onDismiss: () -> Void
    
    @State private var copied = false
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss
    
    var isGenerating: Bool {
        token == nil || token?.isEmpty == true
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // QR Code with copy button inside
                    VStack(spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color(.label).opacity(0.1), radius: 10, x: 0, y: 5)
                            
                            if let token = token, !token.isEmpty {
                                VStack {
                                    QRCodeView(content: token)
                                        .padding(20)
                                        .padding(.bottom, 44) // Space for copy button
                                    
                                    Spacer()
                                }
                                
                                // Copy button overlaid at bottom
                                VStack {
                                    Spacer()
                                    
                                    Button(action: copyToken) {
                                        HStack(spacing: 8) {
                                            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                                .font(.system(size: 16))
                                            Text(copied ? "Copied!" : "Copy")
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundStyle(copied ? .green : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.bottom, 16)
                                }
                            } else {
                                // Loading state
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.5)
                            }
                        }
                        .frame(width: 280, height: 280)
                    }
                    .padding(.top, 40)
                    
                    // Checkmark on left, amount + mint on right
                    HStack(alignment: .center, spacing: 20) {
                        // Success checkmark
                        if !isGenerating {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.1))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        // Amount and mint
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(formatAmount(amount))
                                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                                Text("sats")
                                    .font(.system(size: 20, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Mint below amount
                            if let mint = mintURL?.host {
                                Label(mint, systemImage: "building.columns.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    
                    // Status text
                    if isGenerating {
                        Text("Generating token...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Memo if present
                    if !memo.isEmpty {
                        Text(memo)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Action button
                    if let token = token, !token.isEmpty {
                        Button(action: shareToken) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle(isOfflineMode ? "Offline Token" : "Ecash Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { 
                        onDismiss()
                        dismiss() 
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [token ?? ""])
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
        guard let token = token else { return }
        
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
        guard let token = token else { return }
        
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