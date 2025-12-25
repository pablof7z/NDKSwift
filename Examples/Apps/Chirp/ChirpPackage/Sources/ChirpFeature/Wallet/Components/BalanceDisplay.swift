import SwiftUI

// MARK: - Hero Balance Display

struct BalanceDisplay: View {
    let balance: Int64
    let isLoading: Bool

    @State private var animatedBalance: Int64 = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                loadingView
            } else {
                balanceView
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onChange(of: balance) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animatedBalance = newValue
            }
        }
        .onAppear {
            animatedBalance = balance
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 180, height: 48)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 60, height: 20)
        }
    }

    private var balanceView: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedBalance)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)

                Text("sats")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .offset(y: -8)
            }

        }
    }

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: animatedBalance)) ?? "0"
    }
}

// MARK: - Compact Balance Display

struct CompactBalanceDisplay: View {
    let balance: Int64

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.orange)

            Text(formattedBalance)
                .font(.headline.monospacedDigit())

            Text("sats")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
}

#Preview {
    VStack(spacing: 40) {
        BalanceDisplay(balance: 21000, isLoading: false)
        BalanceDisplay(balance: 0, isLoading: true)
        CompactBalanceDisplay(balance: 1234567)
    }
}
