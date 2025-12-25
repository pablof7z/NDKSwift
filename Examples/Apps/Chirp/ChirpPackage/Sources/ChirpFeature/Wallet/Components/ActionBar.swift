import SwiftUI

// MARK: - Action Bar

struct ActionBar: View {
    let onReceive: () -> Void
    let onSend: () -> Void
    let onScan: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            WalletActionButton(
                title: "Receive",
                systemImage: "arrow.down",
                color: .green,
                action: onReceive
            )

            WalletActionButton(
                title: "Send",
                systemImage: "arrow.up",
                color: .blue,
                action: onSend
            )

            WalletActionButton(
                title: "Scan",
                systemImage: "qrcode.viewfinder",
                color: .orange,
                action: onScan
            )
        }
        .padding(.horizontal)
    }
}

// MARK: - Wallet Action Button

struct WalletActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(color)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.1), in: Circle())

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    VStack {
        ActionBar(
            onReceive: {},
            onSend: {},
            onScan: {}
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
