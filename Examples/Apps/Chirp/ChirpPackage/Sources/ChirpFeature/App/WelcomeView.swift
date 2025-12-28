import SwiftUI
import NDKSwiftCore

struct WelcomeView: View {
    @Environment(ChirpState.self) private var state
    @State private var showingLoginSheet = false
    @State private var isCreatingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Clean branding
            VStack(spacing: 24) {
                Image(systemName: "bird.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text("Chirp")
                        .font(.system(size: 40, weight: .semibold, design: .default))

                    Text("The decentralized social network")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Spacer()

            // Action Buttons
            VStack(spacing: 12) {
                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await createAccount() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreatingAccount {
                            ProgressView()
                        } else {
                            Text("Create Account")
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreatingAccount)

                Button {
                    showingLoginSheet = true
                } label: {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .disabled(isCreatingAccount)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showingLoginSheet) {
            NavigationStack {
                LoginView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func createAccount() async {
        isCreatingAccount = true
        errorMessage = nil

        do {
            let signer = try NDKPrivateKeySigner.generate()
            try await state.authManager.addSession(signer)
            state.handleSuccessfulLogin()
        } catch {
            withAnimation {
                errorMessage = "Failed to create account: \(error.localizedDescription)"
            }
        }

        isCreatingAccount = false
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return WelcomeView()
        .environment(state)
}
