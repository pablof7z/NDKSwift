import SwiftUI
import NDKSwift

struct SessionSelectionView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @Binding var showingSessionSelection: Bool
    @State private var switchingSession: NDKSession?
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.02, blue: 0.08),
                    Color(red: 0.02, green: 0.01, blue: 0.03),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.purple, Color.blue]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Welcome Back")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Choose an account to continue")
                        .font(.system(size: 18))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                
                // Sessions list
                VStack(spacing: 12) {
                    ForEach(nostrManager.authManager.availableSessions) { session in
                        SessionRow(
                            session: session,
                            isLoading: switchingSession?.id == session.id
                        ) {
                            switchToSession(session)
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Add new account button
                Button(action: {
                    showingSessionSelection = false
                }) {
                    Text("Add New Account")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.purple)
                }
                .padding(.bottom, 40)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func switchToSession(_ session: NDKSession) {
        Task {
            switchingSession = session
            do {
                try await nostrManager.authManager.switchToSession(session)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    switchingSession = nil
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: NDKSession
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Avatar placeholder
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(session.pubkey.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.shortIdentifier)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        if session.requiresBiometric {
                            Image(systemName: "faceid")
                                .font(.system(size: 12))
                                .foregroundColor(Color.blue)
                        }
                        
                        Text("Last used: \(session.lastUsed.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}