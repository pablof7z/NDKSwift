import SwiftUI
import NDKSwiftCore
import CoreImage.CIFilterBuiltins
import UIKit

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChirpState.self) private var state

    // Private key state
    @State private var privateKeyInput = ""
    @State private var isLoggingInWithKey = false

    // Remote signer state
    @State private var bunkerInput = ""
    @State private var nostrConnectURL: String?
    @State private var qrCodeImage: UIImage?
    @State private var bunkerSigner: NDKBunkerSigner?
    @State private var isWaitingForConnection = false
    @State private var detectedSigner: KnownSigner?

    // Shared state
    @State private var errorMessage: String?

    private var isLoading: Bool {
        isLoggingInWithKey || isWaitingForConnection
    }

    var body: some View {
        NavigationStack {
            Form {
                // Private Key Section
                Section {
                    SecureField("Enter nsec or private key", text: $privateKeyInput)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .disabled(isLoading)

                    Button {
                        Task {
                            await addAccountWithPrivateKey()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoggingInWithKey {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text("Add with Key")
                            }
                            Spacer()
                        }
                    }
                    .disabled(privateKeyInput.isEmpty || isLoading)
                } header: {
                    Text("Private Key")
                } footer: {
                    Text("Enter your private key in nsec (bech32) or hex format")
                }

                // Remote Signer Section
                Section {
                    if let qrImage = qrCodeImage {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 160, height: 160)

                                if isWaitingForConnection {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                        Text("Waiting...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Scan with your signer")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                                .frame(width: 160, height: 160)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    // Signer app button
                    if let signer = detectedSigner, let url = nostrConnectURL {
                        Button {
                            openSignerApp(signer: signer, connectURL: url)
                        } label: {
                            Label("Open in \(signer.name)", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(isWaitingForConnection)
                    }

                    // Bunker URL paste
                    TextField("Or paste bunker:// URL", text: $bunkerInput)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .disabled(isWaitingForConnection)

                    if !bunkerInput.isEmpty {
                        Button {
                            Task {
                                await connectWithBunkerURL()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Connect")
                                Spacer()
                            }
                        }
                        .disabled(isWaitingForConnection)
                    }
                } header: {
                    Text("Remote Signer")
                } footer: {
                    Text("Use a remote signer app like Primal to sign events")
                }

                // Error Section
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                detectSignerApps()
                await generateNostrConnectQR()
            }
        }
    }

    // MARK: - Private Key

    private func addAccountWithPrivateKey() async {
        isLoggingInWithKey = true
        errorMessage = nil

        do {
            let signer = try NDKPrivateKeySigner.from(userInput: privateKeyInput)
            try await state.authManager.addSession(signer)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoggingInWithKey = false
    }

    // MARK: - Remote Signer

    private func detectSignerApps() {
        for signer in KnownSigner.allCases {
            if let url = URL(string: "\(signer.urlScheme)://"),
               UIApplication.shared.canOpenURL(url) {
                detectedSigner = signer
                return
            }
        }
    }

    private func generateNostrConnectQR() async {
        let ndk = state.ndk
        await Task {
            do {
                let relays = ["wss://relay.damus.io", "wss://relay.primal.net"]
                let localSigner = try NDKPrivateKeySigner.generate()

                let options = NDKBunkerSigner.NostrConnectOptions(
                    name: "Chirp",
                    url: "https://github.com/nostr-dev-kit/ndk-swift",
                    perms: "sign_event:1,sign_event:7"
                )

                let signer = try await NDKBunkerSigner.nostrConnect(
                    ndk: ndk,
                    relays: relays,
                    localSigner: localSigner,
                    options: options
                )

                await MainActor.run { bunkerSigner = signer }

                // Poll for URI
                var url: String?
                for _ in 1...20 {
                    url = await signer.nostrConnectUri
                    if url != nil { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }

                if var url = url {
                    // Add callback
                    let callback = "chirp://nip46"
                    if let encodedCallback = callback.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                        url += "&callback=\(encodedCallback)"
                    }
                    await MainActor.run {
                        nostrConnectURL = url
                        generateQRCode(from: url)
                        isWaitingForConnection = true
                    }
                    Task {
                        await waitForSignerConnection()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }.value
    }

    private func generateQRCode(from string: String) {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")

        guard let outputImage = filter.outputImage else { return }

        // Scale up the QR code
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        // Add white background
        let colorParameters: [String: Any] = [
            "inputImage": scaledImage,
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white
        ]
        guard let coloredImage = CIFilter(name: "CIFalseColor", parameters: colorParameters)?.outputImage else { return }

        if let cgimg = context.createCGImage(coloredImage, from: coloredImage.extent) {
            qrCodeImage = UIImage(cgImage: cgimg)
        }
    }

    private func waitForSignerConnection() async {
        guard let signer = bunkerSigner else { return }

        do {
            _ = try await signer.connect()
            try await state.authManager.addSession(signer)
            await MainActor.run {
                isWaitingForConnection = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isWaitingForConnection = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func connectWithBunkerURL() async {
        let trimmed = bunkerInput.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil

        guard trimmed.hasPrefix("bunker://") || trimmed.hasPrefix("nostrconnect://") else {
            errorMessage = "Invalid URL. Enter a bunker:// or nostrconnect:// URI."
            return
        }

        isWaitingForConnection = true

        let ndk = state.ndk
        await Task {
            do {
                let signer = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: trimmed)
                _ = try await signer.connect()
                try await state.authManager.addSession(signer)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }.value

        isWaitingForConnection = false
    }

    private func openSignerApp(signer: KnownSigner, connectURL: String) {
        guard let url = URL(string: connectURL) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return AddAccountSheet()
        .environment(state)
}
