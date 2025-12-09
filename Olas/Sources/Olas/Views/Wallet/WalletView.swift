// WalletView.swift
import SwiftUI
import NDKSwift

public struct WalletView: View {
    let ndk: NDK
    @ObservedObject var walletViewModel: WalletViewModel

    @State private var showDeposit = false
    @State private var showSend = false
    @State private var showSettings = false

    public init(ndk: NDK, walletViewModel: WalletViewModel) {
        self.ndk = ndk
        self.walletViewModel = walletViewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if walletViewModel.isLoading && !walletViewModel.isSetup {
                    loadingView
                } else if !walletViewModel.isSetup {
                    WalletSetupView(ndk: ndk, walletViewModel: walletViewModel)
                } else {
                    walletContent
                }
            }
            .navigationTitle("Wallet")
            .toolbar {
                if walletViewModel.isSetup {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showDeposit) {
                DepositView(ndk: ndk, walletViewModel: walletViewModel)
            }
            .sheet(isPresented: $showSend) {
                SendView(ndk: ndk, walletViewModel: walletViewModel)
            }
            .sheet(isPresented: $showSettings) {
                WalletSettingsView(walletViewModel: walletViewModel)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading wallet...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var walletContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Balance card
                BalanceCard(
                    balance: walletViewModel.balance,
                    balancesByMint: walletViewModel.balancesByMint,
                    onDeposit: { showDeposit = true },
                    onSend: { showSend = true }
                )
                .padding(.horizontal)

                // Transaction history
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Activity")
                            .font(.headline)

                        Spacer()

                        if !walletViewModel.transactions.isEmpty {
                            NavigationLink {
                                TransactionHistoryView(transactions: walletViewModel.transactions)
                            } label: {
                                Text("See All")
                                    .font(.subheadline)
                                    .foregroundStyle(OlasTheme.Colors.deepTeal)
                            }
                        }
                    }
                    .padding(.horizontal)

                    if walletViewModel.transactions.isEmpty {
                        emptyTransactionsView
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(walletViewModel.transactions.prefix(5)) { transaction in
                                TransactionRow(transaction: transaction)
                                    .padding(.horizontal)

                                if transaction.id != walletViewModel.transactions.prefix(5).last?.id {
                                    Divider()
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await walletViewModel.refreshBalance()
            await walletViewModel.refreshTransactions()
        }
    }

    private var emptyTransactionsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("No transactions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Deposit some sats to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Wallet Settings View

struct WalletSettingsView: View {
    @ObservedObject var walletViewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Configured Mints") {
                    ForEach(walletViewModel.configuredMints, id: \.self) { mintURL in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mintDisplayName(mintURL))
                                    .font(.subheadline)

                                Text(mintURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let balance = walletViewModel.balancesByMint[mintURL] {
                                Text("\(balance) sats")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        // Future: Add mint removal functionality
                    } label: {
                        Label("Add Mint", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Wallet Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsedURL = URL(string: url) else { return url }
        return parsedURL.host ?? url
    }
}
