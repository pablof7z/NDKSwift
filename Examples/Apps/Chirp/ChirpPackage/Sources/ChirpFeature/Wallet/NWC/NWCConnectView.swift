import SwiftUI
import NDKSwiftCore
import UIKit

// MARK: - Known NWC Wallets

enum KnownNWCWallet: CaseIterable {
    case primal
    case other

    var name: String {
        switch self {
        case .primal: return "Primal"
        case .other: return "Wallet"
        }
    }

    var urlScheme: String {
        switch self {
        case .primal: return "nostrnwc+primal"
        case .other: return "nostrnwc"
        }
    }

    var icon: String {
        switch self {
        case .primal: return "bolt.fill"
        case .other: return "wallet.bifold.fill"
        }
    }

    var connectURL: URL? {
        URL(string: "\(urlScheme)://connect")
    }

    func buildDeepLinkURL() -> URL? {
        guard let baseURL = connectURL else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "appname", value: "Chirp"),
            URLQueryItem(name: "callback", value: "chirp://nwc"),
        ]

        return components?.url
    }
}

/// NWC wallet connection flow
struct NWCConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var walletState: WalletState

    @State private var connectionURI = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var detectedWallets: [KnownNWCWallet] = []
    @State private var isDetecting = true
    @State private var awaitingCallback = false
    @State private var pendingWalletName: String?

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

            // Detected Wallets Section
            if isDetecting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Detecting wallets...")
                        .foregroundStyle(.secondary)
                }
            } else if awaitingCallback {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Waiting for \(pendingWalletName ?? "wallet")...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Complete the connection in your wallet app")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            } else if !detectedWallets.isEmpty {
                VStack(spacing: 12) {
                    Text("Open with installed wallet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(detectedWallets, id: \.name) { wallet in
                        Button {
                            openWalletApp(wallet)
                        } label: {
                            HStack {
                                Image(systemName: wallet.icon)
                                Text("Open in \(wallet.name)")
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                }

                // Divider
                HStack {
                    Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                    Text("OR").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                }
                .padding(.horizontal, 32)
            }

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
            } else if !awaitingCallback {
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
        .task {
            await detectWallets()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("nwcCallbackReceived"))) { notification in
            if let uri = notification.userInfo?["uri"] as? String {
                print("[Chirp NWC] Received callback with URI")
                connectionURI = uri
                awaitingCallback = false
                Task { await connect() }
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
                walletBadge("Primal")
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

    private func detectWallets() async {
        isDetecting = true
        var installed: [KnownNWCWallet] = []

        for wallet in KnownNWCWallet.allCases {
            let urlString = "\(wallet.urlScheme)://connect"
            print("[Chirp NWC] Checking wallet \(wallet.name) with URL: \(urlString)")

            if let url = URL(string: urlString) {
                let canOpen = UIApplication.shared.canOpenURL(url)
                print("[Chirp NWC] canOpenURL(\(urlString)) = \(canOpen)")

                if canOpen {
                    installed.append(wallet)
                    print("[Chirp NWC] Detected wallet: \(wallet.name)")
                }
            }
        }

        if installed.isEmpty {
            print("[Chirp NWC] No wallet apps detected")
        }

        detectedWallets = installed
        isDetecting = false
    }

    private func openWalletApp(_ wallet: KnownNWCWallet) {
        guard let url = wallet.buildDeepLinkURL() else {
            errorMessage = "Failed to build connection URL"
            return
        }

        print("[Chirp NWC] Opening wallet with URL: \(url.absoluteString)")

        pendingWalletName = wallet.name
        awaitingCallback = true

        UIApplication.shared.open(url)
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
