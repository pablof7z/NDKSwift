import SwiftUI
import SwiftData

struct RecentTransactionsView: View {
    @EnvironmentObject private var walletManager: WalletManager
    
    // Use reactive transactions from wallet manager
    private var recentTransactions: [Transaction] {
        Array(walletManager.transactions.prefix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: TransactionHistoryView()) {
                    Text("See All")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            if recentTransactions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No transactions yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentTransactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    
    var icon: String {
        switch transaction.type {
        case .mint: return "bolt.fill"
        case .melt: return "bolt"
        case .send: return "arrow.up"
        case .receive: return "arrow.down"
        case .nutzap: return "bolt.heart.fill"
        }
    }
    
    
    var color: Color {
        switch transaction.type {
        case .mint, .receive: return .green
        case .melt, .send, .nutzap: return .orange
        }
    }
    
    var sign: String {
        switch transaction.type {
        case .mint, .receive: return "+"
        case .melt, .send, .nutzap: return "-"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let memo = transaction.memo {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sign)\(transaction.amount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                
                Text(transaction.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Transaction History View
struct TransactionHistoryView: View {
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var selectedFilter: TransactionFilter = .all
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        
        func matches(_ transaction: Transaction) -> Bool {
            switch self {
            case .all: return true
            case .sent: return [.send, .melt, .nutzap].contains(transaction.type)
            case .received: return [.receive, .mint].contains(transaction.type)
            }
        }
    }
    
    var filteredTransactions: [Transaction] {
        walletManager.transactions
            .filter { selectedFilter.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        List {
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(TransactionFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            // Transactions
            ForEach(filteredTransactions) { transaction in
                TransactionDetailRow(transaction: transaction)
            }
        }
        .navigationTitle("Transaction History")
        .platformNavigationBarTitleDisplayMode(inline: true)
        .listStyle(.plain)
    }
}

struct TransactionDetailRow: View {
    let transaction: Transaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TransactionRow(transaction: transaction)
            
            if transaction.status != .completed {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(transaction.status.rawValue.capitalized)
                        .font(.caption2)
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .listRowBackground(Color.secondary.opacity(0.1))
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }
}

extension Transaction.TransactionType {
    var displayName: String {
        switch self {
        case .mint: return "Minted"
        case .melt: return "Melted"
        case .send: return "Sent"
        case .receive: return "Received"
        case .nutzap: return "Nutzapped"
        }
    }
}