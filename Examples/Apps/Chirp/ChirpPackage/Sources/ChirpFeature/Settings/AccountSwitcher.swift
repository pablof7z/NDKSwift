import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

struct AccountSwitcher: View {
    @Environment(ChirpState.self) private var state
    @State private var showAddAccount = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(state.authManager.availableSessions, id: \.id) { session in
                    AccountRow(
                        session: session,
                        isActive: state.authManager.activeSession?.id == session.id,
                        onSwitch: {
                            Task {
                                await switchToSession(session)
                            }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await removeSession(session)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Accounts")
            }

            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    showAddAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Accounts")
        .sheet(isPresented: $showAddAccount) {
            NavigationStack {
                LoginView(isAddingAccount: true)
            }
            .environment(state)
        }
    }

    private func switchToSession(_ session: NDKSession) async {
        errorMessage = nil
        do {
            try await state.authManager.switchToSession(session)
        } catch {
            errorMessage = "Failed to switch account: \(error.localizedDescription)"
        }
    }

    private func removeSession(_ session: NDKSession) async {
        errorMessage = nil
        do {
            try await state.authManager.removeSession(session)
        } catch {
            errorMessage = "Failed to remove account: \(error.localizedDescription)"
        }
    }
}

struct AccountRow: View {
    @Environment(ChirpState.self) private var state
    let session: NDKSession
    let isActive: Bool
    let onSwitch: () -> Void

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?

    var body: some View {
        Button {
            onSwitch()
        } label: {
            HStack(spacing: 12) {
                // Profile picture
                NDKUIProfilePicture(
                    ndk: state.ndk,
                    pubkey: session.pubkey,
                    size: 44
                )

                // Display name and pubkey
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.displayName ?? "...")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(formatPubkey(session.pubkey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Active indicator
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .task {
            profile = state.ndk.profile(for: session.pubkey)
        }
        .buttonStyle(.plain)
    }

    private func formatPubkey(_ pubkey: String) -> String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return String(npub.prefix(16)) + "..."
        }
        return String(pubkey.prefix(12)) + "..."
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return NavigationStack {
        AccountSwitcher()
            .environment(state)
    }
}
