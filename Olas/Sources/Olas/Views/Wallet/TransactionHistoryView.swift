// TransactionHistoryView.swift
import SwiftUI
import NDKSwift

struct TransactionHistoryView: View {
    let transactions: [WalletTransaction]

    var body: some View {
        List {
            ForEach(groupedTransactions.keys.sorted().reversed(), id: \.self) { date in
                Section {
                    ForEach(groupedTransactions[date] ?? []) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                } header: {
                    Text(formatSectionDate(date))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Transaction History")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("Your transaction history will appear here")
                )
            }
        }
    }

    // MARK: - Helpers

    private var groupedTransactions: [Date: [WalletTransaction]] {
        Dictionary(grouping: transactions) { transaction in
            Calendar.current.startOfDay(for: transaction.timestamp)
        }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}
