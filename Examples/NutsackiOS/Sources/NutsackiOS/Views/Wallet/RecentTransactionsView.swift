import SwiftUI
import SwiftData
import NDKSwift

struct RecentTransactionsView: View {
    @Environment(WalletManager.self) private var walletManager
    
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
                            .animation(.easeInOut(duration: 0.3), value: transaction.status)
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
    @Environment(NostrManager.self) private var nostrManager
    @State private var senderProfile: NDKUserProfile?
    
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
        case .mint, .receive, .nutzap: return .green  // Nutzaps are received, so green
        case .melt, .send: return .orange
        }
    }
    
    var sign: String {
        switch transaction.type {
        case .mint, .receive, .nutzap: return "+"  // Nutzaps are received, so positive
        case .melt, .send: return "-"
        }
    }
    
    var displayText: String {
        if transaction.type == .nutzap {
            if let senderProfile = senderProfile {
                let senderName = senderProfile.name ?? senderProfile.displayName ?? "Anonymous"
                return "Nutzap from \(senderName)"
            } else if let senderPubkey = transaction.senderPubkey {
                return "Nutzap from \(senderPubkey.prefix(8))..."
            } else {
                return "Nutzap"
            }
        } else if let memo = transaction.memo {
            return memo
        } else {
            return transaction.type.displayName
        }
    }
    
    var body: some View {
        HStack {
            // Avatar for nutzaps, icon for other transactions
            if transaction.type == .nutzap && transaction.senderPubkey != nil {
                ZStack {
                    // Sender avatar
                    AsyncImage(url: URL(string: senderProfile?.picture ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    
                    // Overlay zap icon
                    Image(systemName: "bolt.heart.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                        .offset(x: 10, y: -10)
                }
                .frame(width: 30, height: 30)
            } else {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 30)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                // Show nutzap comment or transaction type
                if transaction.type == .nutzap && transaction.memo != nil && !transaction.memo!.isEmpty {
                    Text(transaction.memo!)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if transaction.memo != nil && transaction.type != .nutzap {
                    Text(transaction.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(sign)\(transaction.amount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(color)
                    
                    // Show pending indicator
                    if transaction.status == .pending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                }
                
                Text(transaction.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(transaction.status == .pending ? 0.85 : 1.0)
        .task {
            // Fetch sender profile for nutzaps
            if transaction.type == .nutzap, 
               let senderPubkey = transaction.senderPubkey,
               let ndk = nostrManager.ndk {
                
                // Use declarative data source for profile
                let profileDataSource = ndk.observe(
                    filter: NDKFilter(
                        authors: [senderPubkey],
                        kinds: [0]
                    ),
                    maxAge: 3600,
                    cachePolicy: .cacheWithNetwork
                )
                
                for await event in profileDataSource.events {
                    if let profileData = event.content.data(using: .utf8),
                       let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
                        senderProfile = profile
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Transaction History View
struct TransactionHistoryView: View {
    @Environment(WalletManager.self) private var walletManager
    
    @State private var selectedFilter: TransactionFilter = .all
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        
        func matches(_ transaction: Transaction) -> Bool {
            switch self {
            case .all: return true
            case .sent: return [.send, .melt].contains(transaction.type)
            case .received: return [.receive, .mint, .nutzap].contains(transaction.type)
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
    @State private var showOfflineToken = false
    
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
            
            // Show offline token button if available
            if transaction.offlineToken != nil && transaction.type == .send {
                Button(action: { showOfflineToken = true }) {
                    HStack {
                        Image(systemName: "qrcode")
                            .font(.caption)
                        Text("View Token")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .listRowBackground(Color.secondary.opacity(0.1))
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .sheet(isPresented: $showOfflineToken) {
            if let token = transaction.offlineToken {
                OfflineTokenView(
                    token: token,
                    amount: transaction.amount,
                    memo: transaction.memo ?? "",
                    mintURL: nil  // TODO: Store mint URL with transaction
                )
            }
        }
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

