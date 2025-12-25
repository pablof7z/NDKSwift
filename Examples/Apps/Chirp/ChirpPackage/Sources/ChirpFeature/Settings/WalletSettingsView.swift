import SwiftUI
import NDKSwiftCore

/// Wallet settings and type switching
struct WalletSettingsView: View {
    @Bindable var walletState: WalletState

    @State private var showDisconnectConfirm = false

    var body: some View {
        Form {
            // Wallet type section
            Section {
                ForEach(WalletType.allCases, id: \.self) { type in
                    walletTypeRow(type)
                }
            } header: {
                Text("Wallet Type")
            } footer: {
                Text("Choose how you want to manage your sats")
            }

            // Current wallet status
            Section("Status") {
                LabeledContent("Type") {
                    Text(walletState.walletType.displayName)
                }

                LabeledContent("Balance") {
                    Text("\(walletState.balance) sats")
                        .monospacedDigit()
                }

                if walletState.walletType == .cashu {
                    LabeledContent("Mints") {
                        Text("\(walletState.configuredMints.count)")
                    }
                }

                if walletState.walletType == .nwc {
                    LabeledContent("Connection") {
                        connectionStatusView
                    }
                }
            }

            // Wallet-specific settings
            if walletState.isSetUp {
                switch walletState.walletType {
                case .cashu:
                    cashuSettings

                case .nwc:
                    nwcSettings
                }
            }

            // Developer tools link
            Section {
                NavigationLink {
                    WalletDevToolsView(walletState: walletState)
                } label: {
                    Label("Developer Tools", systemImage: "hammer")
                }
            }
        }
        .navigationTitle("Wallet Settings")
    }

    // MARK: - Wallet Type Row

    @ViewBuilder
    private func walletTypeRow(_ type: WalletType) -> some View {
        Button {
            walletState.walletType = type
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if walletState.walletType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusView: some View {
        switch walletState.nwcConnectionStatus {
        case .connected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .foregroundStyle(.green)
            }

        case .connecting:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Connecting...")
                    .foregroundStyle(.secondary)
            }

        case .disconnected:
            Text("Disconnected")
                .foregroundStyle(.secondary)

        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Cashu Settings

    @ViewBuilder
    private var cashuSettings: some View {
        Section("Cashu Wallet") {
            // Mints list
            ForEach(walletState.configuredMints, id: \.self) { mint in
                HStack {
                    VStack(alignment: .leading) {
                        Text(mintDisplayName(mint))
                            .font(.headline)

                        Text(mint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let balance = walletState.balancesByMint[mint] {
                        Text("\(balance) sats")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            // Add mint button
            NavigationLink {
                AddMintView(walletState: walletState)
            } label: {
                Label("Add Mint", systemImage: "plus")
            }
        }
    }

    // MARK: - NWC Settings

    @ViewBuilder
    private var nwcSettings: some View {
        Section("Wallet Connect") {
            Button(role: .destructive) {
                showDisconnectConfirm = true
            } label: {
                Label("Disconnect Wallet", systemImage: "link.badge.minus")
            }
        }
        .confirmationDialog(
            "Disconnect Wallet?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await walletState.disconnectNWC()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can reconnect anytime with a new connection string.")
        }
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.host ?? url
    }
}

/// Add mint view
struct AddMintView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var walletState: WalletState

    @State private var selectedMints: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            MintBrowserView(selectedMints: $selectedMints)
        }
        .navigationTitle("Add Mint")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add") {
                    addMints()
                }
                .disabled(selectedMints.isEmpty)
            }
        }
    }

    private func addMints() {
        // Get current mints and add new ones
        var allMints = Set(walletState.configuredMints)
        allMints.formUnion(selectedMints)

        Task {
            let relays = await walletState.cashuWallet?.resolvedWalletRelays ?? []
            try? await walletState.setupCashuWallet(
                mints: Array(allMints),
                relays: relays
            )
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        WalletSettingsView(walletState: WalletState(ndk: NDK(relayURLs: [])))
    }
}
