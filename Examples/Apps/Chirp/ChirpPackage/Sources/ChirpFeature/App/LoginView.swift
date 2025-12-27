import SwiftUI
import NDKSwiftCore
import CoreImage.CIFilterBuiltins
import UIKit

enum LoginMethod: Hashable {
    case privateKey
    case remoteSigner
}

struct LoginView: View {
    @Environment(ChirpState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// When true, just adds account and dismisses instead of triggering full login flow
    var isAddingAccount: Bool = false

    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white)

                        Text("Sign In")
                            .font(.title.bold())

                        Text("Choose how you want to access your account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 16)

                    // Login Options
                    VStack(spacing: 16) {
                        NavigationLink {
                            PrivateKeyLoginView(isAddingAccount: isAddingAccount)
                        } label: {
                            LoginOptionCard(
                                icon: "key.fill",
                                iconColor: .orange,
                                title: "Private Key",
                                description: "Login with your nsec or hex key",
                                badge: nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            RemoteSignerLoginView(isAddingAccount: isAddingAccount)
                        } label: {
                            LoginOptionCard(
                                icon: "link.badge.plus",
                                iconColor: .blue,
                                title: "Remote Signer",
                                description: "Use NIP-46 bunker connection",
                                badge: "Recommended"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ReadOnlyLoginView(isAddingAccount: isAddingAccount)
                        } label: {
                            LoginOptionCard(
                                icon: "eye",
                                iconColor: .purple,
                                title: "Read-only",
                                description: "View with npub (no signing)",
                                badge: nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    // Security Note
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)

                        Text("Remote signer is recommended for better security. Your private key never leaves your signer app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Spacer(minLength: 48)
                }
            }
        }
        .navigationTitle("Login")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Login Option Card

struct LoginOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let badge: String?

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 48, height: 48)
                .background(iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)

                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue, in: Capsule())
                    }
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

// MARK: - Private Key Login

struct PrivateKeyLoginView: View {
    @Environment(ChirpState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var isAddingAccount: Bool = false

    @State private var privateKeyInput = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Icon Header
                    VStack(spacing: 16) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                            .padding(24)
                            .background(.orange.opacity(0.15), in: Circle())

                        Text("Enter Your Private Key")
                            .font(.title2.bold())

                        Text("Your key is stored securely in the device keychain")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // Input Field
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("nsec1... or hex key", text: $privateKeyInput)
                            .textFieldStyle(.plain)
                            .font(.body.monospaced())
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isInputFocused ? Color.orange : .white.opacity(0.1), lineWidth: 1)
                            }
                            .autocapitalization(.none)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .disabled(isLoggingIn)
                            .focused($isInputFocused)

                        Text("Never share your private key with anyone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Error Message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Login Button
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Sign In")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(privateKeyInput.isEmpty || isLoggingIn)
                    .padding(.horizontal)

                    Spacer(minLength: 48)
                }
            }
        }
        .navigationTitle("Private Key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func login() async {
        isLoggingIn = true
        errorMessage = nil

        do {
            let signer = try NDKPrivateKeySigner.from(userInput: privateKeyInput)
            _ = try await state.authManager.addSession(signer)
            if isAddingAccount {
                dismiss()
            } else {
                state.handleSuccessfulLogin()
            }
        } catch {
            withAnimation {
                errorMessage = error.localizedDescription
            }
        }

        isLoggingIn = false
    }
}

// MARK: - Read-Only Login

struct ReadOnlyLoginView: View {
    @Environment(ChirpState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var isAddingAccount: Bool = false

    @State private var pubkeyInput = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Icon Header
                    VStack(spacing: 16) {
                        Image(systemName: "eye")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)
                            .padding(24)
                            .background(.purple.opacity(0.15), in: Circle())

                        Text("Enter a Public Key")
                            .font(.title2.bold())

                        Text("Browse Nostr in read-only mode without signing capabilities")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // Input Field
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("npub1... or hex pubkey", text: $pubkeyInput)
                            .textFieldStyle(.plain)
                            .font(.body.monospaced())
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isInputFocused ? Color.purple : .white.opacity(0.1), lineWidth: 1)
                            }
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .disabled(isLoggingIn)
                            .focused($isInputFocused)

                        Text("You can view profiles and feeds but cannot post or interact")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Error Message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Login Button
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(pubkeyInput.isEmpty || isLoggingIn)
                    .padding(.horizontal)

                    Spacer(minLength: 48)
                }
            }
        }
        .navigationTitle("Read-only")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func login() async {
        isLoggingIn = true
        errorMessage = nil

        do {
            let trimmed = pubkeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let pubkey: String

            if trimmed.hasPrefix("npub1") {
                // Decode npub to hex
                let decoded = try Bech32.decode(trimmed)
                pubkey = decoded.data.map { String(format: "%02x", $0) }.joined()
            } else if HexValidator.isValid32ByteHex(trimmed) {
                pubkey = trimmed
            } else {
                throw NSError(domain: "LoginError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid public key format. Enter an npub or 64-character hex key."])
            }

            _ = try await state.authManager.addSession(pubkey: pubkey)
            if isAddingAccount {
                dismiss()
            } else {
                state.handleSuccessfulLogin()
            }
        } catch {
            withAnimation {
                errorMessage = error.localizedDescription
            }
        }

        isLoggingIn = false
    }
}

// MARK: - Remote Signer Login

enum KnownSigner: CaseIterable {
    case amber
    case primal
    case other

    var name: String {
        switch self {
        case .amber: return "Amber"
        case .primal: return "Primal"
        case .other: return "Signer App"
        }
    }

    var urlScheme: String {
        switch self {
        case .amber: return "nostrsigner"
        case .primal: return "primal"
        case .other: return "nostrconnect"
        }
    }

    var icon: String {
        switch self {
        case .amber: return "key.fill"
        case .primal: return "bolt.fill"
        case .other: return "arrow.up.forward.app"
        }
    }

    @MainActor
    static func detect() -> KnownSigner? {
        for signer in KnownSigner.allCases {
            let urlString = "\(signer.urlScheme)://"
            print("[Chirp] Checking \(signer.name) with URL: \(urlString)")
            if let url = URL(string: urlString),
               UIApplication.shared.canOpenURL(url) {
                print("[Chirp] ✓ Detected: \(signer.name)")
                return signer
            } else {
                print("[Chirp] ✗ Not available: \(signer.name)")
            }
        }
        print("[Chirp] No signer apps detected")
        return nil
    }
}

struct RemoteSignerLoginView: View {
    @Environment(ChirpState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var isAddingAccount: Bool = false

    @State private var bunkerInput = ""
    @State private var nostrConnectURL: String?
    @State private var qrCodeImage: UIImage?
    @State private var bunkerSigner: NDKBunkerSigner?
    @State private var isWaitingForConnection = false
    @State private var detectedSigner: KnownSigner?
    @State private var errorMessage: String?
    @State private var showingManualEntry = false

    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // QR Code Section
                    VStack(spacing: 20) {
                        ZStack {
                            // Background glow
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.blue.opacity(0.1))
                                .blur(radius: 20)

                            if let qrImage = qrCodeImage {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding(16)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: .black.opacity(0.1), radius: 10)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 232, height: 232)
                                    .overlay {
                                        ProgressView()
                                    }
                            }
                        }

                        if isWaitingForConnection {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Waiting for connection...")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Scan with your Nostr signer app")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 32)

                    // DEBUG: Show detection status
                    #if DEBUG
                    Text("Debug: \(detectedSigner?.name ?? "No signer detected")")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    #endif

                    // Detected Signer App Button
                    if let signer = detectedSigner, let url = nostrConnectURL {
                        Button {
                            openSignerApp(connectURL: url)
                        } label: {
                            HStack {
                                Image(systemName: signer.icon)
                                Text("Open in \(signer.name)")
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isWaitingForConnection)
                        .padding(.horizontal)
                    }

                    // Error Message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(height: 1)
                        Text("OR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)

                    // Manual Entry Section
                    VStack(spacing: 16) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                showingManualEntry.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                Text("Enter bunker URL manually")
                                Spacer()
                                Image(systemName: showingManualEntry ? "chevron.up" : "chevron.down")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)

                        if showingManualEntry {
                            VStack(spacing: 12) {
                                TextField("bunker://...", text: $bunkerInput)
                                    .textFieldStyle(.plain)
                                    .font(.body.monospaced())
                                    .padding()
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .disabled(isWaitingForConnection)

                                Button {
                                    Task { await connectWithBunkerURL() }
                                } label: {
                                    Text("Connect")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(bunkerInput.isEmpty || isWaitingForConnection)
                            }
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    Spacer(minLength: 48)
                }
            }
        }
        .navigationTitle("Remote Signer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detectSignerApps()
            await generateNostrConnectQR()
        }
    }

    private func detectSignerApps() {
        detectedSigner = KnownSigner.detect()
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

                var url: String?
                for _ in 1...20 {
                    url = await signer.nostrConnectUri
                    if url != nil { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }

                if var url = url {
                    let callback = "chirp://nip46"
                    if let encodedCallback = callback.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                        url += "&callback=\(encodedCallback)"
                    }
                    await MainActor.run {
                        nostrConnectURL = url
                        generateQRCode(from: url)
                        isWaitingForConnection = true
                    }
                    Task { await waitForSignerConnection() }
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

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

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
            _ = try await state.authManager.addSession(signer)
            await MainActor.run {
                isWaitingForConnection = false
                if isAddingAccount {
                    dismiss()
                } else {
                    state.handleSuccessfulLogin()
                }
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
            withAnimation {
                errorMessage = "Invalid URL. Enter a bunker:// or nostrconnect:// URI."
            }
            return
        }

        isWaitingForConnection = true

        let ndk = state.ndk
        await Task {
            do {
                let signer = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: trimmed)
                _ = try await signer.connect()
                _ = try await state.authManager.addSession(signer)
                await MainActor.run {
                    bunkerInput = ""
                    if isAddingAccount {
                        dismiss()
                    } else {
                        state.handleSuccessfulLogin()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }.value

        isWaitingForConnection = false
    }

    private func openSignerApp(connectURL: String) {
        guard let url = URL(string: connectURL) else { return }
        print("[Chirp] Opening signer with nostrconnect URL")
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}
