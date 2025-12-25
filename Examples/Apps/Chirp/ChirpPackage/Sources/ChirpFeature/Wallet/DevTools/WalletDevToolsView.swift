import SwiftUI
import NDKSwiftCore
import NDKSwiftCashu

/// Developer tools for wallet internals
struct WalletDevToolsView: View {
    @Bindable var walletState: WalletState

    var body: some View {
        List {
            // Wallet state overview
            Section("Wallet State") {
                LabeledContent("Type") {
                    Text(walletState.walletType.displayName)
                }

                LabeledContent("Balance") {
                    Text("\(walletState.balance) sats")
                        .monospacedDigit()
                }

                LabeledContent("Set Up") {
                    Image(systemName: walletState.isSetUp ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(walletState.isSetUp ? .green : .red)
                }

                LabeledContent("Loading") {
                    Image(systemName: walletState.isLoading ? "circle.fill" : "circle")
                        .foregroundStyle(walletState.isLoading ? .orange : .secondary)
                }
            }

            // Type-specific details
            switch walletState.walletType {
            case .cashu:
                cashuDetails

            case .nwc:
                nwcDetails
            }

            // Transaction stats
            transactionStats

            // Actions
            Section("Actions") {
                Button {
                    Task {
                        await walletState.initializeWallet()
                    }
                } label: {
                    Label("Reload Wallet", systemImage: "arrow.clockwise")
                }

                if walletState.walletType == .cashu {
                    Button {
                        Task {
                            try? await walletState.cashuWallet?.checkAndReconcileProofStates()
                        }
                    } label: {
                        Label("Reconcile Proofs", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .navigationTitle("Wallet Dev Tools")
    }

    // MARK: - Cashu Details

    @ViewBuilder
    private var cashuDetails: some View {
        Section("Cashu Internals") {
            // Mints
            DisclosureGroup("Mints (\(walletState.configuredMints.count))") {
                ForEach(walletState.configuredMints, id: \.self) { mint in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mintDisplayName(mint))
                            .font(.headline)

                        Text(mint)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let balance = walletState.balancesByMint[mint] {
                            Text("\(balance) sats")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Proof states
            NavigationLink {
                ProofStatesView(walletState: walletState)
            } label: {
                Label("Proof States", systemImage: "checklist")
            }

            // Wallet events
            NavigationLink {
                WalletEventsView(walletState: walletState)
            } label: {
                Label("Wallet Events", systemImage: "list.bullet.rectangle")
            }

            // Relay health
            NavigationLink {
                WalletRelayHealthView(walletState: walletState)
            } label: {
                Label("Relay Health", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    // MARK: - NWC Details

    @ViewBuilder
    private var nwcDetails: some View {
        Section("NWC Internals") {
            LabeledContent("Status") {
                connectionStatusBadge
            }

            LabeledContent("Wallet") {
                Text(walletState.nwcWallet != nil ? "Connected" : "Not configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch walletState.nwcConnectionStatus {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connecting:
            Label("Connecting", systemImage: "arrow.clockwise")
                .foregroundStyle(.orange)
        case .disconnected:
            Label("Disconnected", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Transaction Stats

    @ViewBuilder
    private var transactionStats: some View {
        Section("Transactions") {
            LabeledContent("Total") {
                Text("\(walletState.transactions.count)")
            }

            let incoming = walletState.transactions.filter { $0.direction == .incoming }
            let outgoing = walletState.transactions.filter { $0.direction == .outgoing }

            LabeledContent("Incoming") {
                Text("\(incoming.count) (\(incoming.reduce(0) { $0 + $1.amount }) sats)")
                    .foregroundStyle(.green)
            }

            LabeledContent("Outgoing") {
                Text("\(outgoing.count) (\(outgoing.reduce(0) { $0 + $1.amount }) sats)")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func mintDisplayName(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.host ?? url
    }
}

// MARK: - Proof States View

struct ProofStatesView: View {
    @Bindable var walletState: WalletState

    @State private var proofsByMint: [String: [ProofInfo]] = [:]
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading proofs...")
            } else if proofsByMint.isEmpty {
                ContentUnavailableView(
                    "No Proofs",
                    systemImage: "doc.text",
                    description: Text("No proofs in wallet")
                )
            } else {
                ForEach(Array(proofsByMint.keys).sorted(), id: \.self) { mint in
                    Section(mintDisplayName(mint)) {
                        if let proofs = proofsByMint[mint] {
                            ForEach(proofs) { proof in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Amount: \(proof.amount)")
                                            .font(.headline)
                                        Text("Keyset: \(proof.keysetId.prefix(8))...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(proof.state.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(stateColor(proof.state).opacity(0.2), in: Capsule())
                                        .foregroundStyle(stateColor(proof.state))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Proof States")
        .task {
            await loadProofs()
        }
    }

    private func loadProofs() async {
        guard let wallet = walletState.cashuWallet else {
            isLoading = false
            return
        }

        let unspentProofs = await wallet.getUnspentProofs()

        var result: [String: [ProofInfo]] = [:]
        for (mint, proofs) in unspentProofs {
            result[mint] = proofs.map { proof in
                ProofInfo(
                    id: proof.C,
                    amount: Int(proof.amount),
                    keysetId: proof.keysetID,
                    state: .available
                )
            }
        }

        proofsByMint = result
        isLoading = false
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.host ?? url
    }

    private func stateColor(_ state: ProofState) -> Color {
        switch state {
        case .available: return .green
        case .pending: return .orange
        case .spent: return .red
        }
    }
}

struct ProofInfo: Identifiable {
    let id: String
    let amount: Int
    let keysetId: String
    let state: ProofState
}

enum ProofState: String {
    case available = "Available"
    case pending = "Pending"
    case spent = "Spent"
}

// MARK: - Wallet Events View

struct WalletEventsView: View {
    @Bindable var walletState: WalletState

    var body: some View {
        List {
            // Show recent transactions as a proxy for wallet events
            if walletState.transactions.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "list.bullet",
                    description: Text("Wallet activity will appear here")
                )
            } else {
                Section("Recent Activity") {
                    ForEach(walletState.transactions.prefix(20), id: \.id) { tx in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tx.type.displayName)
                                    .font(.headline)
                                Spacer()
                                Text("\(tx.direction == .incoming ? "+" : "-")\(tx.amount) sats")
                                    .font(.subheadline)
                                    .foregroundStyle(tx.direction == .incoming ? .green : .red)
                            }

                            Text(tx.status.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(tx.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Wallet Events")
    }
}

// MARK: - Wallet Relay Health View

struct WalletRelayHealthView: View {
    @Bindable var walletState: WalletState
    @Environment(ChirpState.self) private var state
    @State private var connectedRelayURLs: Set<String> = []

    var body: some View {
        List {
            Section("Wallet Relays") {
                if walletState.walletRelays.isEmpty {
                    Text("No relays configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(walletState.walletRelays, id: \.self) { relay in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(relay)
                                    .font(.headline)
                            }

                            Spacer()

                            let isConnected = connectedRelayURLs.contains(relay)
                            Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isConnected ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Relay Health")
        .task {
            let connected = await state.ndk.pool.connectedRelays()
            connectedRelayURLs = Set(connected.map { $0.url })
        }
    }
}

#Preview {
    NavigationStack {
        WalletDevToolsView(walletState: WalletState(ndk: NDK(relayURLs: [])))
    }
}
