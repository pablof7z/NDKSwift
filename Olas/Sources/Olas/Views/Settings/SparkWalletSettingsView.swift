import SwiftUI
import NDKSwift

public struct SparkWalletSettingsView: View {
    let ndk: NDK

    @State private var connectionStatus: SparkConnectionStatus = .disconnected
    @State private var balance: Int64 = 0
    @State private var lightningAddress: String?
    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showDisconnectAlert = false
    @State private var isLoading = false
    @State private var error: String?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        List {
            statusSection

            if connectionStatus == .connected {
                balanceSection
                addressSection
                actionsSection
            } else {
                setupSection
            }
        }
        .navigationTitle("Spark Wallet")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await checkConnection()
        }
        .sheet(isPresented: $showCreateWallet) {
            CreateSparkWalletView(ndk: ndk, onComplete: { await checkConnection() })
        }
        .sheet(isPresented: $showImportWallet) {
            ImportSparkWalletView(ndk: ndk, onComplete: { await checkConnection() })
        }
        .alert("Disconnect Wallet", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await disconnect() }
            }
        } message: {
            Text("This will disconnect your Spark wallet. You can reconnect later using your mnemonic.")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: connectionStatus.icon)
                    .foregroundStyle(connectionStatus.color)
                Text(connectionStatus.description)
                Spacer()
                if isLoading {
                    ProgressView()
                }
            }
        } header: {
            Text("Connection Status")
        }
    }

    private var balanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatSats(balance))
                    .font(.title.bold())
            }
            .padding(.vertical, 8)
        }
    }

    private var addressSection: some View {
        Section {
            if let address = lightningAddress {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lightning Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(address)
                            .font(.body.monospaced())
                        Spacer()
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = address
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            } else {
                Button("Setup Lightning Address") {
                    // Show lightning address registration
                }
            }
        } header: {
            Text("Receiving")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await sync() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Wallet")
                }
            }

            Button(role: .destructive) {
                showDisconnectAlert = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect Wallet")
                }
            }
        }
    }

    private var setupSection: some View {
        Section {
            Button {
                showCreateWallet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                    Text("Create New Wallet")
                }
            }

            Button {
                showImportWallet = true
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Import Existing Wallet")
                }
            }
        } header: {
            Text("Get Started")
        } footer: {
            Text("Spark is a self-custodial Bitcoin wallet. Your keys, your coins. You'll need your mnemonic phrase to recover your wallet.")
        }
    }

    // MARK: - Actions

    private func checkConnection() async {
        isLoading = true
        defer { isLoading = false }

        // Check if spark wallet is connected via zapManager
        // For now, set disconnected - would integrate with actual SparkWallet instance
        connectionStatus = .disconnected
    }

    private func sync() async {
        isLoading = true
        defer { isLoading = false }
        // Sync wallet via SparkWallet instance
    }

    private func disconnect() async {
        isLoading = true
        defer { isLoading = false }
        // Disconnect via SparkWallet instance
        connectionStatus = .disconnected
        balance = 0
        lightningAddress = nil
    }

    // MARK: - Helpers

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(formatted) sats"
    }
}

// MARK: - Connection Status

enum SparkConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(String)

    var icon: String {
        switch self {
        case .disconnected: return "bolt.slash.fill"
        case .connecting: return "bolt.horizontal.fill"
        case .connected: return "bolt.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return OlasTheme.Colors.zapGold
        case .error: return .red
        }
    }

    var description: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Create Wallet View

struct CreateSparkWalletView: View {
    let ndk: NDK
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mnemonic: String?
    @State private var mnemonicConfirmed = false
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let mnemonic = mnemonic {
                    mnemonicDisplay(mnemonic)
                } else {
                    createPrompt
                }
            }
            .padding()
            .navigationTitle("Create Wallet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var createPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.deepTeal)

            Text("Create Your Wallet")
                .font(.title2.bold())

            Text("A new 12-word recovery phrase will be generated. Write it down and store it safely - this is the only way to recover your funds.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await createWallet() }
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Generate Wallet")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.deepTeal)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(isCreating)
        }
    }

    private func mnemonicDisplay(_ mnemonic: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Your Recovery Phrase")
                .font(.title2.bold())

            Text("Write these words down in order. Never share them with anyone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                let words = mnemonic.split(separator: " ")
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                        Text(String(word))
                            .font(.body.monospaced())
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Toggle("I have written down my recovery phrase", isOn: $mnemonicConfirmed)

            Button {
                Task {
                    await onComplete()
                    dismiss()
                }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(mnemonicConfirmed ? OlasTheme.Colors.deepTeal : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(!mnemonicConfirmed)
        }
    }

    private func createWallet() async {
        isCreating = true
        defer { isCreating = false }

        // Would call SparkWallet.createWallet() here
        // For now, generate a placeholder
        mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    }
}

// MARK: - Import Wallet View

struct ImportSparkWalletView: View {
    let ndk: NDK
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mnemonic = ""
    @State private var isImporting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Import Wallet")
                    .font(.title2.bold())

                Text("Enter your 12 or 24-word recovery phrase to restore your wallet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextEditor(text: $mnemonic)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await importWallet() }
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Import Wallet")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidMnemonic ? .blue : .gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(!isValidMnemonic || isImporting)

                Spacer()
            }
            .padding()
            .navigationTitle("Import Wallet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isValidMnemonic: Bool {
        let words = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return words.count == 12 || words.count == 24
    }

    private func importWallet() async {
        isImporting = true
        defer { isImporting = false }

        // Would call SparkWallet.connect(mnemonic:) here
        await onComplete()
        dismiss()
    }
}
