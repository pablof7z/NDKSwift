import SwiftUI

struct AddMintView: View {
    @ObservedObject var walletManager: OlasWalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var mintURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @FocusState private var isTextFieldFocused: Bool
    
    // Popular mints
    private let popularMints = [
        ("Minibits", "https://mint.minibits.cash/Bitcoin"),
        ("Cashu Space", "https://testnut.cashu.space"),
        ("8333.space", "https://8333.space:3338"),
        ("LNbits Legend", "https://legend.lnbits.com/cashu/api/v1/AptDNABNBXv8gpuywhx6NV")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Header illustration
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(hex: "667EEA").opacity(0.3),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 100
                                    )
                                )
                                .frame(width: 200, height: 200)
                                .blur(radius: 30)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color(hex: "667EEA").opacity(0.5), radius: 20)
                        }
                        .padding(.top, OlasDesign.Spacing.xl)
                        
                        // Instructions
                        VStack(spacing: OlasDesign.Spacing.sm) {
                            Text("Add a Cashu Mint")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(OlasDesign.Colors.text)
                            
                            Text("Connect to a mint to store and manage your ecash")
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // URL Input
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                            Text("Mint URL")
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                            
                            HStack {
                                TextField("https://mint.example.com", text: $mintURL)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(OlasDesign.Typography.body)
                                    .foregroundColor(OlasDesign.Colors.text)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .focused($isTextFieldFocused)
                                
                                Button {
                                    showingScanner = true
                                    OlasDesign.Haptic.selection()
                                } label: {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.title2)
                                        .foregroundStyle(OlasDesign.Colors.primary)
                                }
                            }
                            .padding(OlasDesign.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                    .fill(OlasDesign.Colors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                            .stroke(
                                                isTextFieldFocused ? OlasDesign.Colors.primary : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            )
                            
                            if let error = errorMessage {
                                Text(error)
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundStyle(OlasDesign.Colors.error)
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Popular Mints
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                            Text("Popular Mints")
                                .font(OlasDesign.Typography.bodyBold)
                                .foregroundStyle(OlasDesign.Colors.text)
                                .padding(.horizontal, OlasDesign.Spacing.md)
                            
                            VStack(spacing: OlasDesign.Spacing.sm) {
                                ForEach(popularMints, id: \.1) { name, url in
                                    PopularMintRow(
                                        name: name,
                                        url: url,
                                        isAdded: walletManager.mintURLs.contains(url)
                                    ) {
                                        mintURL = url
                                        Task {
                                            await addMint()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
                
                // Loading overlay
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: OlasDesign.Spacing.md) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Connecting to mint...")
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(.white)
                        }
                        .padding(OlasDesign.Spacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                .fill(OlasDesign.Colors.surface)
                        )
                        .shadow(radius: 20)
                    }
                }
            }
            .navigationTitle("Add Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        Task {
                            await addMint()
                        }
                    }
                    .disabled(mintURL.isEmpty || isLoading)
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { result in
                    mintURL = result
                }
            }
        }
    }
    
    private func addMint() async {
        guard !mintURL.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        isTextFieldFocused = false
        
        do {
            try await walletManager.addMint(mintURL)
            OlasDesign.Haptic.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            OlasDesign.Haptic.error()
        }
        
        isLoading = false
    }
}

struct PopularMintRow: View {
    let name: String
    let url: String
    let isAdded: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OlasDesign.Spacing.md) {
                // Icon
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isAdded ? [Color.gray, Color.gray.opacity(0.8)] : [Color(hex: "667EEA"), Color(hex: "764BA2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("₿")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                // Details
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundStyle(OlasDesign.Colors.text)
                    
                    Text(url.replacingOccurrences(of: "https://", with: ""))
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status
                if isAdded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                        Text("Added")
                            .font(OlasDesign.Typography.caption)
                            .foregroundStyle(OlasDesign.Colors.textSecondary)
                    }
                } else {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(OlasDesign.Colors.primary)
                }
            }
            .padding(OlasDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(OlasDesign.Colors.surface)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAdded)
    }
}