import SwiftUI
import NDKSwift

struct WalletView: View {
    @ObservedObject var viewModel: NostrViewModel
    @StateObject private var walletViewModel = WalletViewModel()
    @State private var showingSendSheet = false
    @State private var showingReceiveSheet = false
    @State private var showingDepositSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance Card
                balanceCard
                
                // Quick Actions
                actionButtons
                
                // Recent Transactions
                transactionsSection
                
                // Wallet Status
                walletStatusSection
            }
            .padding()
        }
        .onAppear {
            walletViewModel.setup(with: viewModel)
        }
        .sheet(isPresented: $showingSendSheet) {
            SendNutzapView(walletViewModel: walletViewModel)
        }
        .sheet(isPresented: $showingReceiveSheet) {
            ReceiveNutzapView(walletViewModel: walletViewModel)
        }
        .sheet(isPresented: $showingDepositSheet) {
            DepositView(walletViewModel: walletViewModel)
        }
    }
    
    private var balanceCard: some View {
        VStack(spacing: 12) {
            Text("Balance")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack {
                Text(formatSats(walletViewModel.balance))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("sats")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            if walletViewModel.isLoading {
                ProgressView("Loading balance...")
                    .font(.caption)
            } else if !walletViewModel.errorMessage.isEmpty {
                Text(walletViewModel.errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                showingDepositSheet = true
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    Text("Deposit")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            
            Button(action: {
                showingReceiveSheet = true
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("Receive")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
            }
            
            Button(action: {
                showingSendSheet = true
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    Text("Send")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            .disabled(walletViewModel.balance <= 0)
        }
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)
            
            if walletViewModel.transactions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No transactions yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
            } else {
                ForEach(walletViewModel.transactions.prefix(5), id: \.id) { transaction in
                    TransactionRowView(transaction: transaction)
                }
            }
        }
    }
    
    private var walletStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet Status")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(walletViewModel.isWalletReady ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(walletViewModel.isWalletReady ? "Ready" : "Setting up...")
                        .font(.caption)
                }
                
                if !walletViewModel.configuredMints.isEmpty {
                    Text("Mints: \(walletViewModel.configuredMints.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ForEach(walletViewModel.configuredMints.prefix(3), id: \.self) { mint in
                        Text("• \(mint)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )
        }
    }
    
    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}

struct TransactionRowView: View {
    let transaction: WalletTransaction
    
    var body: some View {
        HStack {
            Image(systemName: transaction.type == .received ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundColor(transaction.type == .received ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.caption)
                    .lineLimit(1)
                Text(formatDate(transaction.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(transaction.type == .received ? "+" : "-")\(transaction.amount) sats")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(transaction.type == .received ? .green : .orange)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        WalletView(viewModel: NostrViewModel())
            .navigationTitle("Wallet")
    }
}