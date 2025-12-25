import SwiftUI
import NDKSwiftCore
import NDKSwiftCashu

/// Cashu wallet setup flow
struct CashuSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChirpState.self) private var state
    @Bindable var walletState: WalletState

    @State private var step: SetupStep = .welcome
    @State private var selectedMints: Set<String> = []
    @State private var customMintURL = ""
    @State private var isSettingUp = false
    @State private var errorMessage: String?

    enum SetupStep {
        case welcome
        case selectMints
        case confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome:
                welcomeStep

            case .selectMints:
                selectMintsStep

            case .confirm:
                confirmStep
            }
        }
        .navigationTitle("Cashu Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Welcome Step

    @ViewBuilder
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)

            Text("Cashu Wallet")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                featureRow(icon: "lock.shield", title: "Self-Custodial", description: "You control your ecash tokens")
                featureRow(icon: "bolt", title: "Lightning Compatible", description: "Send and receive via Lightning")
                featureRow(icon: "eye.slash", title: "Private", description: "Transactions don't reveal your identity")
            }
            .padding(.horizontal)

            Spacer()

            Button {
                withAnimation { step = .selectMints }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Select Mints Step

    @ViewBuilder
    private var selectMintsStep: some View {
        VStack(spacing: 0) {
            // Custom mint input
            HStack {
                TextField("https://mint.example.com", text: $customMintURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                Button {
                    addCustomMint()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(customMintURL.isEmpty)
            }
            .padding()

            Divider()

            // Mint browser
            MintBrowserView(selectedMints: $selectedMints)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Next") {
                    withAnimation { step = .confirm }
                }
                .disabled(selectedMints.isEmpty)
            }
        }
    }

    private func addCustomMint() {
        var url = customMintURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure https
        if !url.lowercased().hasPrefix("http") {
            url = "https://" + url
        }

        guard URL(string: url) != nil else {
            errorMessage = "Invalid URL"
            return
        }

        selectedMints.insert(url)
        customMintURL = ""
    }

    // MARK: - Confirm Step

    @ViewBuilder
    private var confirmStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Ready to Create")
                .font(.title.bold())

            Text("Your wallet will be configured with \(selectedMints.count) mint\(selectedMints.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Selected mints list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(selectedMints), id: \.self) { mint in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(mintDisplayName(mint))
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            if isSettingUp {
                ProgressView("Creating wallet...")
                    .padding()
            } else {
                Button {
                    Task { await createWallet() }
                } label: {
                    Text("Create Wallet")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }

            Button {
                withAnimation { step = .selectMints }
            } label: {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom)
        }
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.host ?? url
    }

    private func createWallet() async {
        isSettingUp = true
        defer { isSettingUp = false }

        do {
            // Get user's relay list or use defaults
            let relays = await state.ndk.pool.connectedRelays().map { $0.url }
            let walletRelays = relays.isEmpty ? ["wss://relay.damus.io", "wss://nos.lol"] : Array(relays.prefix(3))

            walletState.walletType = .cashu
            try await walletState.setupCashuWallet(
                mints: Array(selectedMints),
                relays: walletRelays
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return NavigationStack {
        CashuSetupView(walletState: WalletState(ndk: ndk))
            .environment(state)
    }
}
