import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var showLogin = false
    @State private var showCreateAccount = false

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Image(systemName: "water.waves")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Olas")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(OlasTheme.Colors.deepTeal)
                .padding(.top, 16)

            Text("Share moments. Ride the wave.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    showCreateAccount = true
                } label: {
                    Text("Create Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }

                Button {
                    showLogin = true
                } label: {
                    Text("I have a Nostr account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showLogin) {
            LoginView(authViewModel: authViewModel)
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView(authViewModel: authViewModel)
        }
    }
}
