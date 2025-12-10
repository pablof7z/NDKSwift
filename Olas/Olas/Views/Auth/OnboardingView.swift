import SwiftUI

struct OnboardingView: View {
    var authViewModel: AuthViewModel
    @State private var showLogin = false
    @State private var showCreateAccount = false

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            OlasLogo(size: 100)

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
                .accessibilityIdentifier("createAccountButton")

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
                .accessibilityIdentifier("loginButton")
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
