// TransactionRow.swift
import SwiftUI
import NDKSwift

struct TransactionRow: View {
    let transaction: WalletTransaction

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 44, height: 44)

                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transactionTitle)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 4) {
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let status = statusText {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(status)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedAmount)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(amountColor)

                Text("sats")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed Properties

    private var transactionTitle: String {
        switch transaction.type {
        case .mint:
            return "Lightning Deposit"
        case .melt:
            return "Lightning Withdrawal"
        case .nutzapSent:
            return "Nutzap Sent"
        case .nutzapReceived:
            return "Nutzap Received"
        case .send:
            return "Cashu Sent"
        case .receive:
            return "Cashu Received"
        case .swap:
            return "Mint Transfer"
        }
    }

    private var iconName: String {
        switch transaction.type {
        case .mint, .nutzapReceived, .receive:
            return "arrow.down"
        case .melt, .nutzapSent, .send:
            return "arrow.up"
        case .swap:
            return "arrow.left.arrow.right"
        }
    }

    private var iconColor: Color {
        switch transaction.direction {
        case .incoming:
            return .green
        case .outgoing:
            return OlasTheme.Colors.zapGold
        case .neutral:
            return .blue
        }
    }

    private var iconBackgroundColor: Color {
        iconColor.opacity(0.15)
    }

    private var amountColor: Color {
        switch transaction.direction {
        case .incoming:
            return .green
        case .outgoing:
            return .primary
        case .neutral:
            return .primary
        }
    }

    private var formattedAmount: String {
        let prefix = transaction.direction == .incoming ? "+" : (transaction.direction == .outgoing ? "-" : "")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let amount = formatter.string(from: NSNumber(value: transaction.amount)) ?? "\(transaction.amount)"
        return "\(prefix)\(amount)"
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: transaction.timestamp, relativeTo: Date())
    }

    private var statusText: String? {
        switch transaction.status {
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .completed:
            return nil
        case .failed:
            return "Failed"
        case .expired:
            return "Expired"
        }
    }

    private var statusColor: Color {
        switch transaction.status {
        case .pending, .processing:
            return .orange
        case .completed:
            return .green
        case .failed, .expired:
            return .red
        }
    }
}
