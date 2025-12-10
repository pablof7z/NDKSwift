import SwiftUI
import NDKSwift

struct SparkWalletSettingsView: View {
    @Bindable var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showDisconnectAlert = false
    @State private var showLightningAddressSetup = false
    @State private var showBackupPhrase = false

    public var body: some View {
        List {
            statusSection

            if walletManager.connectionStatus == .connected {
                balanceSection
                currencySection
                addressSection
                actionsSection
                switchWalletSection
            } else {
                setupSection
            }

            if let error = walletManager.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Spark Wallet")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showCreateWallet) {
            CreateSparkWalletView(walletManager: walletManager)
        }
        .sheet(isPresented: $showImportWallet) {
            ImportSparkWalletView(walletManager: walletManager)
        }
        .sheet(isPresented: $showLightningAddressSetup) {
            LightningAddressSetupView(walletManager: walletManager)
        }
        .sheet(isPresented: $showBackupPhrase) {
            BackupPhraseView(walletManager: walletManager)
        }
        .alert("Disconnect Wallet", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await walletManager.disconnect(clearMnemonic: true) }
            }
        } message: {
            Text("This will disconnect your Spark wallet. You can reconnect later using your mnemonic.")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: walletManager.connectionStatus.icon)
                    .foregroundStyle(walletManager.connectionStatus.color)
                Text(walletManager.connectionStatus.description)
                Spacer()
                if walletManager.isLoading {
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
                Text(formatSats(walletManager.balance))
                    .font(.title.bold())
            }
            .padding(.vertical, 8)
        }
    }

    private var currencySection: some View {
        Section {
            Picker("Currency", selection: $walletManager.preferredCurrency) {
                Text("USD").tag("USD")
                Text("EUR").tag("EUR")
                Text("GBP").tag("GBP")
                Text("JPY").tag("JPY")
                Text("CHF").tag("CHF")
                Text("CAD").tag("CAD")
                Text("AUD").tag("AUD")
                Text("BRL").tag("BRL")
                Text("MXN").tag("MXN")
            }

            Toggle("Show Fiat as Primary", isOn: $walletManager.showFiatAsPrimary)
        } header: {
            Text("Display Currency")
        } footer: {
            Text("Choose how your balance is displayed. Tap the balance to quickly switch between sats and fiat.")
        }
    }

    private var addressSection: some View {
        Section {
            if let address = walletManager.lightningAddress {
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
                    showLightningAddressSetup = true
                }
            }
        } header: {
            Text("Receiving")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await walletManager.sync() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Wallet")
                }
            }

            Button {
                showBackupPhrase = true
            } label: {
                HStack {
                    Image(systemName: "key.fill")
                    Text("Backup Recovery Phrase")
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

    private var switchWalletSection: some View {
        Section {
            Button {
                Task {
                    await walletManager.disconnect(clearMnemonic: false)
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Switch to Cashu Wallet")
                }
            }
        } header: {
            Text("Switch Wallet")
        } footer: {
            Text("Your Spark wallet will remain available. You can switch back anytime.")
        }
    }

    private var setupSection: some View {
        Section {
            Button {
                showCreateWallet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(OlasTheme.Colors.brandPrimary)
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

    // MARK: - Helpers

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(formatted) sats"
    }
}

// MARK: - Create Wallet View

struct CreateSparkWalletView: View {
    var walletManager: SparkWalletManager

    @Environment(\.dismiss) private var dismiss

    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(OlasTheme.Colors.zapGold)

                    Text("Create Your Wallet")
                        .font(.title2.bold())

                    Text("A new self-custodial Bitcoin wallet will be created. You can backup your recovery phrase later from the wallet settings.")
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
                            Text("Create Wallet")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.brandPrimary)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isCreating)
                }
                .padding()
            }
            .navigationTitle("Create Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createWallet() async {
        isCreating = true
        defer { isCreating = false }

        do {
            _ = try await walletManager.createWallet()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Import Wallet View

struct ImportSparkWalletView: View {
    var walletManager: SparkWalletManager

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
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

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

        let cleanedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        do {
            try await walletManager.importWallet(mnemonic: cleanedMnemonic)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Lightning Address Setup View

struct LightningAddressSetupView: View {
    var walletManager: SparkWalletManager

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isRegistering = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(OlasTheme.Colors.zapGold)

                Text("Setup Lightning Address")
                    .font(.title2.bold())

                Text("Choose a username for your Lightning address. You'll be able to receive payments at username@spark.money")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    TextField("username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Text("@spark.money")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await registerAddress() }
                } label: {
                    HStack {
                        if isRegistering {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Register Address")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidUsername ? OlasTheme.Colors.zapGold : .gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(!isValidUsername || isRegistering)

                Spacer()
            }
            .padding()
            .navigationTitle("Lightning Address")
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

    private var isValidUsername: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func registerAddress() async {
        isRegistering = true
        defer { isRegistering = false }

        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            try await walletManager.registerLightningAddress(cleanedUsername)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Backup Phrase View

struct BackupPhraseView: View {
    var walletManager: SparkWalletManager

    @Environment(\.dismiss) private var dismiss
    @State private var mnemonic: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(OlasTheme.Colors.zapGold)

                    Text("Recovery Phrase")
                        .font(.title2.bold())

                    Text("Write these words down and store them safely. Anyone with this phrase can access your funds.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let mnemonic = mnemonic {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            let words = mnemonic.split(separator: " ")
                            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                HStack {
                                    Text("\(index + 1).")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(String(word))
                                        .font(.body.monospaced())
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                            }
                        }
                        .padding()

                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = mnemonic
                            #endif
                            copied = true
                        } label: {
                            HStack {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy to Clipboard")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .cornerRadius(12)
                        }
                    } else {
                        Text("Unable to retrieve recovery phrase")
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                mnemonic = walletManager.getMnemonic()
            }
        }
    }
}
