import SwiftUI
import SwiftData
import NDKSwift
// import Popovers - Removed for build compatibility

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    
    @State private var selectedTab: Tab = .wallet
    @State private var urlState: URLState?
    @State private var showScanner = false
    @State private var scannedInvoice: String?
    @State private var showInvoicePreview = false
    
    enum Tab {
        case wallet
        case contacts
        case scanner
        case mints
        case settings
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            NDKAuthView(authManager: nostrManager.authManager) {
                // Main app interface - shown when authenticated
                TabView(selection: $selectedTab) {
                    WalletView(urlState: $urlState)
                        .tabItem {
                            Label("Wallet", systemImage: "bitcoinsign.circle")
                        }
                        .tag(Tab.wallet)
                    
                    ContactsView()
                        .tabItem {
                            Label("Contacts", systemImage: "person.2")
                        }
                        .tag(Tab.contacts)
                    
                    // Scanner "tab" - doesn't show content, just triggers action
                    Color.clear
                        .tabItem {
                            VStack {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
                                    
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .scaleEffect(1.3) // Make it more prominent
                                .offset(y: -8) // Lift it up more
                                
                                Text("Scan")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fontWeight(.medium)
                            }
                        }
                        .tag(Tab.scanner)
                    
                    MintsView()
                        .tabItem {
                            Label("Mints", systemImage: "building.columns")
                        }
                        .tag(Tab.mints)
                    
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(Tab.settings)
                }
                .tint(.orange)
                .background(Color.black)
                .onChange(of: selectedTab) { _, newValue in
                    if newValue == .scanner {
                        showScanner = true
                        // Reset to previous tab (wallet by default)
                        selectedTab = .wallet
                    }
                }
            } authenticationContent: {
                // Custom authentication UI
                AuthenticationView()
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            handleUrl(url)
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { scannedValue in
                handleScannedValue(scannedValue)
            }
        }
        .sheet(isPresented: $showInvoicePreview) {
            if let invoice = scannedInvoice {
                LightningInvoicePreviewView(invoice: invoice)
            }
        }
    }
    
    
    private func handleUrl(_ url: URL) {
        print("URL passed to application: \(url.absoluteString)")
        
        if url.scheme == "cashu" || url.scheme == "nostr" {
            selectedTab = .wallet
            urlState = URLState(url: url.absoluteString, timestamp: Date())
        }
    }
    
    private func handleScannedValue(_ scannedValue: String) {
        showScanner = false
        
        // Check if it's a lightning invoice
        if isLightningInvoice(scannedValue) {
            scannedInvoice = scannedValue
            showInvoicePreview = true
        } else {
            // Handle other QR codes (cashu tokens, nostr, etc.)
            selectedTab = .wallet
            urlState = URLState(url: scannedValue, timestamp: Date())
        }
    }
    
    private func isLightningInvoice(_ text: String) -> Bool {
        let cleanText = text.lowercased().replacingOccurrences(of: "lightning:", with: "")
        return cleanText.starts(with: "lnbc") || cleanText.starts(with: "lntb") || cleanText.starts(with: "lnbcrt")
    }
}

struct URLState: Equatable {
    let url: String
    let timestamp: Date
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var showCreateAccount = false
    @State private var showImportAccount = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // Logo and Title
                VStack(spacing: 20) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.orange.gradient)
                    
                    Text("Nutsack")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Lightning-fast payments with Nostr")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Auth buttons
                VStack(spacing: 16) {
                    Button(action: { showCreateAccount = true }) {
                        Label("Create Account", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.gradient)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: { showImportAccount = true }) {
                        Label("Import with nsec", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .background(
                RadialGradient(
                    gradient: Gradient(colors: [Color(white: 0.1), .black]),
                    center: .top,
                    startRadius: 100,
                    endRadius: 600
                )
            )
            .navigationDestination(isPresented: $showCreateAccount) {
                CreateAccountView()
            }
            .navigationDestination(isPresented: $showImportAccount) {
                ImportAccountView()
            }
        }
    }
}

// MARK: - Lightning Invoice Preview View
struct LightningInvoicePreviewView: View {
    let invoice: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @Environment(\.modelContext) private var modelContext
    
    @State private var decodedAmount: Int64?
    @State private var decodedDescription: String?
    @State private var availableBalance: Int = 0
    @State private var isPaying = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Lightning Invoice")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Review payment details before proceeding")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Payment Details Card
                    VStack(spacing: 0) {
                        if let amount = decodedAmount {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Amount")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("\(amount) sats")
                                            .font(.title)
                                            .fontWeight(.bold)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Fee (est.)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("~1 sat")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("Total Payment")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    Text("\(amount + 1) sats")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(amount + 1 > availableBalance ? .red : .orange)
                                }
                            }
                            .padding(20)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(16)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 30))
                                    .foregroundColor(.orange)
                                
                                Text("Invalid Invoice")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                Text("Unable to decode the lightning invoice")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(20)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(16)
                        }
                    }
                    
                    // Description if available
                    if let description = decodedDescription, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            Text(description)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(12)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(12)
                        }
                    }
                    
                    // Balance Check
                    if let amount = decodedAmount {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Balance")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("\(availableBalance) sats")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                if amount + 1 > availableBalance {
                                    Text("Insufficient balance")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                } else {
                                    Text("✓ Sufficient balance")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(12)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Payment Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: payInvoice) {
                        if isPaying {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Pay")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(decodedAmount == nil || isPaying || (decodedAmount ?? 0) + 1 > availableBalance)
                }
            }
        }
        .onAppear {
            decodeInvoice()
            loadBalance()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showSuccess) {
            if let amount = decodedAmount {
                MeltSuccessView(amount: Int(amount)) {
                    dismiss()
                }
            }
        }
    }
    
    private func decodeInvoice() {
        var cleanInvoice = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanInvoice.starts(with: "lightning:") {
            cleanInvoice = String(cleanInvoice.dropFirst(10))
        }
        
        if cleanInvoice.lowercased().starts(with: "lnbc") || cleanInvoice.lowercased().starts(with: "lntb") || cleanInvoice.lowercased().starts(with: "lnbcrt") {
            let prefix = cleanInvoice.prefix(4)
            let trimmed = cleanInvoice.dropFirst(4)
            var amountStr = ""
            var multiplier: Int64 = 1
            
            for char in trimmed {
                if char.isNumber {
                    amountStr.append(char)
                } else if char == "m" {
                    multiplier = 100
                    break
                } else if char == "u" {
                    multiplier = 100000
                    break
                } else if char == "n" {
                    multiplier = 100000000
                    break
                } else if char == "p" {
                    multiplier = 100000000000
                    break
                } else {
                    break
                }
            }
            
            if let amount = Int64(amountStr) {
                decodedAmount = (amount * multiplier) / 1000
            }
            
            decodedDescription = "Lightning payment"
        }
    }
    
    private func loadBalance() {
        Task {
            do {
                let balance = try await walletManager.getBalance()
                await MainActor.run {
                    availableBalance = Int(balance)
                }
            } catch {
                print("Failed to get balance: \(error)")
            }
        }
    }
    
    private func payInvoice() {
        guard let amount = decodedAmount else { return }
        
        isPaying = true
        
        Task {
            do {
                let _ = try await walletManager.payLightning(
                    invoice: invoice.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: amount
                )
                
                // Transaction will be recorded automatically via NIP-60 history events
                await MainActor.run {
                    showSuccess = true
                    isPaying = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isPaying = false
                }
            }
        }
    }
}