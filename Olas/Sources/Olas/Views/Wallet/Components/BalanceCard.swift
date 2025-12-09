// BalanceCard.swift
import SwiftUI

struct BalanceCard: View {
    let balance: Int64
    let balancesByMint: [String: Int64]
    let onDeposit: () -> Void
    let onSend: () -> Void

    @State private var showMintBreakdown = false

    var body: some View {
        VStack(spacing: 24) {
            // Balance display
            VStack(spacing: 8) {
                Text("Balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatSats(balance))
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    Text("sats")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Mint breakdown toggle
                if balancesByMint.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showMintBreakdown.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(balancesByMint.count) mints")
                                .font(.caption)
                            Image(systemName: showMintBreakdown ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Mint breakdown
            if showMintBreakdown {
                VStack(spacing: 8) {
                    ForEach(Array(balancesByMint.keys.sorted()), id: \.self) { mintURL in
                        if let mintBalance = balancesByMint[mintURL] {
                            HStack {
                                Text(mintDisplayName(mintURL))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(formatSats(mintBalance)) sats")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onDeposit) {
                    Label("Deposit", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WalletActionButtonStyle(color: OlasTheme.Colors.deepTeal))

                Button(action: onSend) {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WalletActionButtonStyle(color: OlasTheme.Colors.zapGold))
                .disabled(balance == 0)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.secondary.opacity(0.1))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let url = URL(string: url) else { return url }
        return url.host ?? url.absoluteString
    }
}

// MARK: - Button Style

struct WalletActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
