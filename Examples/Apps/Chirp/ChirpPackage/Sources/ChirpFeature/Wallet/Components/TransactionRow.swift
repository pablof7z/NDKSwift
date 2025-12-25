import SwiftUI
import NDKSwiftCashu

/// Flat transaction list item
struct TransactionRow: View {
    let transaction: WalletTransaction

    var body: some View {
        HStack(spacing: 12) {
            // Direction indicator
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)

                if let memo = transaction.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedAmount)
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)
                    .foregroundStyle(amountColor)

                if transaction.status == .pending {
                    Text("Pending")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var iconName: String {
        switch transaction.direction {
        case .incoming:
            return "arrow.down.left"
        case .outgoing:
            return "arrow.up.right"
        case .neutral:
            return "arrow.left.arrow.right"
        }
    }

    private var iconColor: Color {
        switch transaction.direction {
        case .incoming:
            return .green
        case .outgoing:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private var title: String {
        transaction.type.displayName
    }

    private var amountColor: Color {
        switch transaction.direction {
        case .incoming:
            return .green
        case .outgoing:
            return .primary
        case .neutral:
            return .secondary
        }
    }

    private var formattedAmount: String {
        let prefix = transaction.direction == .incoming ? "+" : "-"
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let amount = formatter.string(from: NSNumber(value: abs(transaction.amount))) ?? "0"
        return "\(prefix)\(amount)"
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: transaction.timestamp, relativeTo: Date())
    }
}

#Preview {
    List {
        TransactionRow(transaction: WalletTransaction(
            id: "1",
            type: .mint,
            amount: 5000,
            direction: .incoming,
            status: .completed,
            memo: "From wallet",
            timestamp: Date().addingTimeInterval(-3600)
        ))

        TransactionRow(transaction: WalletTransaction(
            id: "2",
            type: .melt,
            amount: 1000,
            direction: .outgoing,
            status: .completed,
            timestamp: Date().addingTimeInterval(-7200)
        ))

        TransactionRow(transaction: WalletTransaction(
            id: "3",
            type: .nutzapReceived,
            amount: 100,
            direction: .incoming,
            status: .pending,
            memo: "Great post!",
            timestamp: Date().addingTimeInterval(-86400)
        ))
    }
    .listStyle(.plain)
}
