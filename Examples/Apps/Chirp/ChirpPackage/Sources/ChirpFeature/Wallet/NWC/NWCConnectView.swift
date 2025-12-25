import SwiftUI
import NDKSwiftCore

/// NWC wallet connection flow
struct NWCConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var walletState: WalletState

    @State private var connectionURI = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "link.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Wallet Connect")
                .font(.largeTitle.bold())

            Text("Connect to your favorite Lightning wallet using NIP-47")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Connection URI input
            VStack(alignment: .leading, spacing: 8) {
                Text("Connection String")
                    .font(.headline)

                HStack {
                    TextField("nostr+walletconnect://...", text: $connectionURI, axis: .vertical)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                            .padding(8)
                            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text("Get this from your wallet app (Alby, Mutiny, etc.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()

            // Connect button
            if isConnecting {
                ProgressView("Connecting...")
                    .padding()
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(connectionURI.isEmpty ? Color.secondary.opacity(0.3) : .blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(connectionURI.isEmpty)
                .padding(.horizontal)
            }

            // Compatible wallets info
            compatibleWalletsSection
        }
        .padding(.bottom)
        .navigationTitle("Wallet Connect")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRScannerView { scannedValue in
                    connectionURI = scannedValue
                    showScanner = false
                }
            }
        }
    }

    @ViewBuilder
    private var compatibleWalletsSection: some View {
        VStack(spacing: 8) {
            Text("Compatible with")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                walletBadge("Alby")
                walletBadge("Mutiny")
                walletBadge("Zeus")
                walletBadge("Others")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.bottom)
    }

    @ViewBuilder
    private func walletBadge(_ name: String) -> some View {
        Text(name)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.2), in: Capsule())
    }

    private func connect() async {
        let uri = connectionURI.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !uri.isEmpty else {
            errorMessage = "Please enter a connection string"
            return
        }

        // Validate URI format
        guard uri.lowercased().hasPrefix("nostr+walletconnect://") ||
              uri.lowercased().hasPrefix("nostrwalletconnect://") else {
            errorMessage = "Invalid connection string format"
            return
        }

        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            walletState.walletType = .nwc
            try await walletState.connectNWC(connectionURI: uri)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        NWCConnectView(walletState: WalletState(ndk: NDK(relayURLs: [])))
    }
}
