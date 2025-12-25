import SwiftUI
import NDKSwiftCore
import NDKSwiftCashu

// MARK: - Wallet View

struct WalletView: View {
    @Environment(ChirpState.self) private var state
    @State private var walletState: WalletState?
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showScan = false

    var body: some View {
        Group {
            if let walletState = walletState {
                if walletState.isSetUp {
                    connectedWalletView(walletState)
                } else {
                    setupView(walletState)
                }
            } else {
                loadingView
            }
        }
        .navigationTitle("Wallet")
        .task {
            await initializeWallet()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Initializing wallet...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connected Wallet View

    @ViewBuilder
    private func connectedWalletView(_ walletState: WalletState) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Balance Card
                BalanceDisplay(
                    balance: walletState.balance,
                    isLoading: walletState.isLoading
                )

                // Action Buttons
                ActionBar(
                    onReceive: { showReceive = true },
                    onSend: { showSend = true },
                    onScan: { showScan = true }
                )

                // Wallet Info Card
                walletInfoCard(walletState)

                // Transactions Section
                transactionsSection(walletState)
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            await walletState.initializeWallet()
        }
        .sheet(isPresented: $showReceive) {
            NavigationStack {
                ReceiveView(walletState: walletState)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSend) {
            NavigationStack {
                SendView(walletState: walletState)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScan) {
            NavigationStack {
                QRScannerView { scannedValue in
                    showScan = false
                    handleScannedValue(scannedValue, walletState: walletState)
                }
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Wallet Info Card

    @ViewBuilder
    private func walletInfoCard(_ walletState: WalletState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: walletState.walletType == .cashu ? "bitcoinsign.circle.fill" : "link.circle.fill")
                .font(.title2)
                .foregroundStyle(walletState.walletType == .cashu ? .orange : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(walletState.walletType.displayName)
                    .font(.subheadline.weight(.medium))

                if walletState.walletType == .cashu && !walletState.configuredMints.isEmpty {
                    Text("\(walletState.configuredMints.count) mint\(walletState.configuredMints.count == 1 ? "" : "s") connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Transactions Section

    @ViewBuilder
    private func transactionsSection(_ walletState: WalletState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Recent Activity")
                .padding(.bottom, 12)

            if walletState.transactions.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right.circle",
                    title: "No Transactions",
                    message: "Your transactions will appear here"
                )
                .frame(minHeight: 200)
            } else {
                VStack(spacing: 0) {
                    ForEach(walletState.transactions, id: \.id) { transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal)

                        if transaction.id != walletState.transactions.last?.id {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Setup View

    @ViewBuilder
    private func setupView(_ walletState: WalletState) -> some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                Text("Set Up Your Wallet")
                    .font(.title.bold())

                Text("Choose how you want to manage your sats")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Wallet Options
            VStack(spacing: 16) {
                NavigationLink {
                    CashuSetupView(walletState: walletState)
                } label: {
                    WalletSetupOptionCard(
                        icon: "bitcoinsign.circle.fill",
                        iconColor: .orange,
                        title: "Cashu Wallet",
                        description: "Self-custodial ecash. Private and secure.",
                        isRecommended: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    NWCConnectView(walletState: walletState)
                } label: {
                    WalletSetupOptionCard(
                        icon: "link.circle.fill",
                        iconColor: .blue,
                        title: "Wallet Connect",
                        description: "Connect your existing lightning wallet.",
                        isRecommended: false
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func initializeWallet() async {
        if walletState == nil {
            let newState = WalletState(ndk: state.ndk)
            walletState = newState
            await newState.initializeWallet()
        }
    }

    private func handleScannedValue(_ value: String, walletState: WalletState) {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("lnbc") || lowercased.hasPrefix("lightning:") {
            showSend = true
        } else if lowercased.hasPrefix("nostr+walletconnect://") || lowercased.hasPrefix("nostrwalletconnect://") {
            Task {
                try? await walletState.connectNWC(connectionURI: value)
            }
        }
    }
}

// MARK: - Wallet Setup Option Card

struct WalletSetupOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isRecommended: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)

                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue, in: Capsule())
                    }
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        WalletView()
            .environment(ChirpState(
                ndk: NDK(relayURLs: []),
                authManager: NDKAuthManager(ndk: NDK(relayURLs: [])),
                relayCollection: NDKRelayCollection(ndk: NDK(relayURLs: []))
            ))
    }
}
