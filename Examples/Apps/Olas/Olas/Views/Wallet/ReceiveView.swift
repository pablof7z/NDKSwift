import SwiftUI
import CoreImage.CIFilterBuiltins

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ReceiveView: View {
    @ObservedObject var walletManager: OlasWalletManager
    @Environment(\.dismiss) var dismiss
    
    @State private var amount = ""
    @State private var description = ""
    @State private var invoice = ""
    @State private var isGenerating = false
    @State private var showingCopiedAlert = false
    
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
                                        colors: [Color(hex: "4ECDC4"), Color(hex: "44A08D")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                )
                            
                            Text("Receive Sats")
                                .font(OlasDesign.Typography.title)
                                .foregroundStyle(OlasDesign.Colors.text)
                        }
                        .padding(.top, OlasDesign.Spacing.lg)
                        
                        // Input fields
                        VStack(spacing: OlasDesign.Spacing.md) {
                            // Amount input
                            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                                Text("Amount (optional)")
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                                
                                HStack {
                                    Image(systemName: "bitcoinsign.circle")
                                        .font(.title2)
                                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                                    
                                    TextField("0", text: $amount)
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
                            
                            // Description input
                            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                                Text("Description (optional)")
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                                
                                HStack {
                                    Image(systemName: "text.alignleft")
                                        .font(.title2)
                                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                                    
                                    TextField("What's this for?", text: $description)
                                        .font(OlasDesign.Typography.body)
                                        .foregroundStyle(OlasDesign.Colors.text)
                                }
                                .padding(OlasDesign.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                        .fill(OlasDesign.Colors.surface)
                                )
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Generate button
                        OlasButton(
                            title: "Generate Invoice",
                            action: {
                                Task {
                                    await generateInvoice()
                                }
                            },
                            style: .primary,
                            isLoading: isGenerating
                        )
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Invoice display
                        if !invoice.isEmpty {
                            VStack(spacing: OlasDesign.Spacing.md) {
                                // QR Code
                                if let qrImage = generateQRCode(from: invoice) {
                                    #if canImport(UIKit)
                                    Image(uiImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 250, height: 250)
                                        .padding()
                                        .background(Color.white)
                                        .cornerRadius(OlasDesign.CornerRadius.lg)
                                    #elseif canImport(AppKit)
                                    Image(nsImage: qrImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 250, height: 250)
                                        .padding()
                                        .background(Color.white)
                                        .cornerRadius(OlasDesign.CornerRadius.lg)
                                    #endif
                                }
                                
                                // Invoice text
                                VStack(spacing: OlasDesign.Spacing.sm) {
                                    Text("Lightning Invoice")
                                        .font(OlasDesign.Typography.caption)
                                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                                    
                                    Text(invoice)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                                        .lineLimit(3)
                                        .truncationMode(.middle)
                                        .padding()
                                        .background(OlasDesign.Colors.surface)
                                        .cornerRadius(OlasDesign.CornerRadius.md)
                                }
                                .padding(.horizontal, OlasDesign.Spacing.md)
                                
                                // Copy button
                                OlasButton(
                                    title: showingCopiedAlert ? "Copied!" : "Copy Invoice",
                                    action: {
                                        copyInvoice()
                                    },
                                    style: .secondary
                                )
                                .padding(.horizontal, OlasDesign.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Receive")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    .navigationBarTrailing
                    #else
                    .automatic
                    #endif
                }()) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(OlasDesign.Colors.text)
                }
            }
        }
    }
    
    private func generateInvoice() async {
        isGenerating = true
        defer { isGenerating = false }
        
        let satsAmount = Int64(amount) ?? 0
        
        do {
            invoice = try await walletManager.generateInvoice(
                amount: satsAmount,
                description: description.isEmpty ? nil : description
            )
            OlasDesign.Haptic.success()
        } catch {
            print("Error generating invoice: \(error)")
            OlasDesign.Haptic.error()
        }
    }
    
    private func copyInvoice() {
        #if os(iOS)
        UIPasteboard.general.string = invoice
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(invoice, forType: .string)
        #endif
        
        showingCopiedAlert = true
        OlasDesign.Haptic.success()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopiedAlert = false
        }
    }
    
    #if canImport(UIKit)
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        
        return nil
    }
    #elseif canImport(AppKit)
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        
        return nil
    }
    #endif
}

// End of ReceiveView.swift
