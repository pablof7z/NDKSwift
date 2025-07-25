import SwiftUI
import NDKSwift
import CoreImage.CIFilterBuiltins

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ZapView: View {
    let event: NDKEvent
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedAmount = 1000
    @State private var customAmount = ""
    @State private var comment = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lightningInvoice: String?
    @State private var showingQRCode = false
    @State private var recipientProfile: NDKUserProfile?
    
    let presetAmounts = [100, 500, 1000, 5000, 10000, 50000]
    
    var body: some View {
        NavigationView {
            VStack(spacing: OlasDesign.Spacing.lg) {
                // Header
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(OlasDesign.Colors.warning)
                    
                    Text("Send Lightning Zap")
                        .font(OlasDesign.Typography.title)
                        .foregroundStyle(OlasDesign.Colors.text)
                }
                .padding(.top, OlasDesign.Spacing.lg)
                
                // Amount Selection
                VStack(spacing: OlasDesign.Spacing.md) {
                    Text("Select Amount (sats)")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                    
                    // Preset amounts
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: OlasDesign.Spacing.sm) {
                        ForEach(presetAmounts, id: \.self) { amount in
                            OlasButton(
                                title: formatAmount(amount),
                                action: {
                                    selectedAmount = amount
                                    customAmount = ""
                                    OlasDesign.Haptic.selection()
                                },
                                style: selectedAmount == amount ? .primary : .secondary
                            )
                        }
                    }
                    
                    // Custom amount
                    HStack {
                        OlasTextField(
                            text: $customAmount,
                            placeholder: "Custom amount",
                            icon: "bitcoinsign.circle"
                        )
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: customAmount) { _, newValue in
                            if !newValue.isEmpty, let amount = Int(newValue) {
                                selectedAmount = amount
                            }
                        }
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
                
                // Comment
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Text("Add a comment (optional)")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                    
                    OlasTextField(
                        text: $comment,
                        placeholder: "Your message...",
                        icon: "text.bubble"
                    )
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
                
                // Recipient info
                if let profile = recipientProfile {
                    VStack(spacing: OlasDesign.Spacing.xs) {
                        if profile.lud16 != nil || profile.lud06 != nil {
                            Label("Lightning enabled", systemImage: "checkmark.circle.fill")
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.success)
                        }
                        
                        if let lud16 = profile.lud16 {
                            Text(lud16)
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.error)
                        .padding(.horizontal, OlasDesign.Spacing.md)
                }
                
                // Action buttons
                VStack(spacing: OlasDesign.Spacing.md) {
                    OlasButton(
                        title: "Generate Invoice",
                        action: {
                            Task {
                                await generateInvoice()
                            }
                        },
                        style: .primary,
                        isLoading: isLoading
                    )
                    
                    OlasButton(
                        title: "Cancel",
                        action: {
                            dismiss()
                        },
                        style: .secondary
                    )
                }
                .padding(OlasDesign.Spacing.md)
            }
            .background(OlasDesign.Colors.background)
            #if os(iOS)
            .navigationBarHidden(true)
            #else
            .toolbar(.hidden)
            #endif
        }
        .sheet(isPresented: $showingQRCode) {
            if let invoice = lightningInvoice {
                QRCodeView(invoice: invoice)
            }
        }
        .task {
            await fetchRecipientInfo()
        }
    }
    
    private func formatAmount(_ sats: Int) -> String {
        if sats >= 1000 {
            return "\(sats / 1000)k"
        }
        return "\(sats)"
    }
    
    private func fetchRecipientInfo() async {
        guard let ndk = appState.ndk,
              let profileManager = ndk.profileManager else { return }
        
        // Observe profile
        for await profile in await profileManager.observe(for: event.pubkey) {
            await MainActor.run {
                recipientProfile = profile
                
                if let profile = profile {
                    if profile.lud16 == nil && profile.lud06 == nil {
                        errorMessage = "This user doesn't have Lightning enabled"
                    }
                } else {
                    errorMessage = "Unable to load user profile"
                }
            }
            break // Only need first result
        }
    }
    
    private func generateInvoice() async {
        guard appState.ndk != nil else {
            errorMessage = "Network not connected"
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // For now, we'll show a message about wallet configuration
        // In a real implementation, this would use NDKZapManager
        
        await MainActor.run {
            errorMessage = "Lightning wallet not configured. Use a Nostr client with wallet support to send zaps."
            isLoading = false
        }
        
        // Example of how it would work with a configured wallet:
        /*
        do {
            let zapManager = NDKZapManager(ndk: ndk)
            await zapManager.configureDefaults()
            
            let recipient = NDKUser(pubkey: event.pubkey)
            let result = try await zapManager.zap(
                event: event,
                recipient: recipient,
                amountSats: Int64(selectedAmount),
                comment: comment.isEmpty ? nil : comment
            )
            
            await MainActor.run {
                // Success! Close the sheet
                dismiss()
                OlasDesign.Haptic.success()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
                OlasDesign.Haptic.error()
            }
        }
        */
    }
}

struct QRCodeView: View {
    let invoice: String
    @Environment(\.dismiss) var dismiss
    
    #if canImport(UIKit)
    var qrImage: UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(invoice.utf8), forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        
        return nil
    }
    #elseif canImport(AppKit)
    var qrImage: NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(invoice.utf8), forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        
        return nil
    }
    #endif
    
    var body: some View {
        NavigationView {
            VStack(spacing: OlasDesign.Spacing.lg) {
                Text("Lightning Invoice")
                    .font(OlasDesign.Typography.title)
                
                if let image = qrImage {
                    #if canImport(UIKit)
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                    .frame(width: 300, height: 300)
                    .background(Color.white)
                    .cornerRadius(OlasDesign.CornerRadius.md)
                    #endif
                }
                
                Text(invoice)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                    .padding()
                    .background(OlasDesign.Colors.surface)
                    .cornerRadius(OlasDesign.CornerRadius.sm)
                    .padding(.horizontal)
                
                OlasButton(title: "Copy Invoice", action: {
                    #if os(iOS)
                    UIPasteboard.general.string = invoice
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(invoice, forType: .string)
                    #endif
                    OlasDesign.Haptic.success()
                })
                
                OlasButton(title: "Done", action: {
                    dismiss()
                }, style: .secondary)
            }
            .padding()
            .background(OlasDesign.Colors.background)
            #if os(iOS)
            .navigationBarHidden(true)
            #else
            .toolbar(.hidden)
            #endif
        }
    }
}