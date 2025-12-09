import SwiftUI
import NDKSwift

struct AccountSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showNsec = false
    @State private var nsec: String?
    @State private var npub: String?
    @State private var copiedMessage: String?

    var body: some View {
        List {
            Section("Public Key") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your npub (shareable)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(npub ?? "Loading...")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            if let npub { copyToClipboard(npub, label: "npub") }
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Back up your private key", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)

                    Text("Your private key (nsec) is the only way to recover your account. Store it securely and never share it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if showNsec, let nsec {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nsec)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)

                            Button {
                                copyToClipboard(nsec, label: "nsec")
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy Private Key")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button {
                            showNsec = true
                        } label: {
                            HStack {
                                Image(systemName: "eye")
                                Text("Reveal Private Key")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Private Key Backup")
            } footer: {
                Text("Keep your private key safe. Anyone with access to it controls your account.")
            }

            if let message = copiedMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadKeys()
        }
    }

    private func loadKeys() {
        guard let signer = authViewModel.signer else { return }
        npub = try? signer.npub
        nsec = try? signer.nsec
    }

    private func copyToClipboard(_ value: String, label: String) {
        UIPasteboard.general.string = value
        copiedMessage = "\(label) copied to clipboard"
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedMessage = nil
        }
    }
}
