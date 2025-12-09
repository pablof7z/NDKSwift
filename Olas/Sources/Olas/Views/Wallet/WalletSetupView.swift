// WalletSetupView.swift
import SwiftUI
import NDKSwift

struct WalletSetupView: View {
    let ndk: NDK
    @ObservedObject var walletViewModel: WalletViewModel

    @StateObject private var mintDiscovery: MintDiscoveryViewModel
    @State private var currentStep: SetupStep = .welcome
    @State private var isSettingUp = false
    @State private var setupError: Error?
    @State private var customMintURL = ""

    enum SetupStep {
        case welcome
        case selectMints
        case confirm
    }

    init(ndk: NDK, walletViewModel: WalletViewModel) {
        self.ndk = ndk
        self.walletViewModel = walletViewModel
        self._mintDiscovery = StateObject(wrappedValue: MintDiscoveryViewModel(ndk: ndk))
    }

    var body: some View {
        VStack {
            switch currentStep {
            case .welcome:
                welcomeStep

            case .selectMints:
                mintSelectionStep

            case .confirm:
                confirmStep
            }
        }
        .alert("Setup Error", isPresented: .init(
            get: { setupError != nil },
            set: { if !$0 { setupError = nil } }
        )) {
            Button("OK") { setupError = nil }
        } message: {
            Text(setupError?.localizedDescription ?? "Unknown error")
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(OlasTheme.Colors.deepTeal.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "creditcard.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(OlasTheme.Colors.deepTeal)
            }

            // Title
            VStack(spacing: 12) {
                Text("Set Up Your Wallet")
                    .font(.title.bold())

                Text("Store ecash in your Nostr wallet to send and receive nutzaps - instant, private payments on Nostr.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Instant Payments",
                    description: "Send tips without waiting for confirmations"
                )

                FeatureRow(
                    icon: "eye.slash.fill",
                    title: "Private",
                    description: "Ecash tokens are unlinkable to your identity"
                )

                FeatureRow(
                    icon: "icloud.fill",
                    title: "Synced",
                    description: "Your wallet follows you across devices"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Continue button
            Button {
                withAnimation {
                    currentStep = .selectMints
                }
                Task {
                    await mintDiscovery.discoverMints()
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(OlasTheme.Colors.deepTeal)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Mint Selection Step

    private var mintSelectionStep: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Choose Mints")
                    .font(.title2.bold())

                Text("Select one or more Cashu mints to store your ecash. You can always add more later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            // Custom mint URL entry
            HStack {
                TextField("Enter mint URL (https://...)", text: $customMintURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button {
                    addCustomMint()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(customMintURL.isEmpty || !isValidMintURL(customMintURL))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Mint list - mints stream in as they are discovered
            if mintDiscovery.discoveredMints.isEmpty && mintDiscovery.selectedMints.isEmpty {
                VStack(spacing: 12) {
                    if mintDiscovery.isDiscovering {
                        ProgressView()
                        Text("Discovering mints...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No mints discovered. Enter a mint URL above.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                MintSelectionView(
                    mints: mintDiscovery.discoveredMints,
                    selectedMints: $mintDiscovery.selectedMints
                )
            }

            // Footer
            VStack(spacing: 12) {
                Button {
                    withAnimation {
                        currentStep = .confirm
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(mintDiscovery.selectedMints.isEmpty)

                Button {
                    withAnimation {
                        currentStep = .welcome
                    }
                } label: {
                    Text("Back")
                        .font(.subheadline)
                }
            }
            .padding(24)
        }
    }

    private func isValidMintURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              (scheme == "https" || scheme == "http"),
              url.host != nil else {
            return false
        }
        return true
    }

    private func addCustomMint() {
        let trimmed = customMintURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidMintURL(trimmed) else { return }
        mintDiscovery.selectedMints.insert(trimmed)
        customMintURL = ""
    }

    // MARK: - Confirm Step

    private var confirmStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Summary
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Ready to Set Up")
                    .font(.title2.bold())

                Text("Your wallet will be configured with:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Selected mints
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected Mints")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(mintDiscovery.selectedMints), id: \.self) { mintURL in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text(mintDisplayName(mintURL))
                            .font(.subheadline)

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button {
                    Task {
                        await completeSetup()
                    }
                } label: {
                    if isSettingUp {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Text("Create Wallet")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OlasTheme.Colors.deepTeal)
                .disabled(isSettingUp)

                Button {
                    withAnimation {
                        currentStep = .selectMints
                    }
                } label: {
                    Text("Back")
                        .font(.subheadline)
                }
                .disabled(isSettingUp)
            }
            .padding(24)
        }
    }

    // MARK: - Helpers

    private func completeSetup() async {
        isSettingUp = true
        defer { isSettingUp = false }

        do {
            // Get user's write relays or use defaults
            let relays = OlasConstants.defaultRelays

            try await walletViewModel.setupWallet(
                mints: mintDiscovery.selectedMintURLs,
                relays: relays
            )
        } catch {
            setupError = error
        }
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsedURL = URL(string: url) else { return url }
        return parsedURL.host ?? url
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(OlasTheme.Colors.deepTeal)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
