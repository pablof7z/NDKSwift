import SwiftUI
import NDKSwiftCore

struct WelcomeView: View {
    @Environment(ChirpState.self) private var state
    @State private var showingLoginSheet = false
    @State private var isCreatingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Simple dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Clean branding
                VStack(spacing: 24) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white)

                    VStack(spacing: 8) {
                        Text("Chirp")
                            .font(.system(size: 40, weight: .semibold, design: .default))
                            .foregroundStyle(.white)

                        Text("The decentralized social network")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
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
                                    .tint(.black)
                            } else {
                                Text("Create Account")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isCreatingAccount)

                    Button {
                        showingLoginSheet = true
                    } label: {
                        Text("Sign In")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isCreatingAccount)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
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
    let relayCollection = NDKRelayCollection(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager, relayCollection: relayCollection)

    return WelcomeView()
        .environment(state)
}
