import SwiftUI
import NDKSwift

struct BackupKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    let session: NDKSession
    var onComplete: (() -> Void)? = nil
    
    @State private var copiedPrivateKey = false
    @State private var savedKey = false
    @State private var privateKey: String?
    @State private var nsec: String?
    
    var displayName: String {
        session.profileName ?? session.shortIdentifier
    }
    
    var body: some View {
        ZStack {
            // Dark gradient background
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
            
            VStack(spacing: 30) {
                // Warning header
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.yellow.opacity(0.3),
                                        Color.orange.opacity(0.2),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)
                        
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.yellow, Color.orange]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(spacing: 12) {
                        Text("SAVE YOUR KEYS")
                            .font(.system(size: 32, weight: .black))
                            .tracking(2)
                            .foregroundColor(.white)
                        
                        Text("This is your only way back. Guard it with your life!")
                            .font(.system(size: 14, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                .padding(.top, 40)
            
            Spacer()
            
                // Key display
                VStack(spacing: 20) {
                    Text("Your private key (nsec)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    VStack(spacing: 16) {
                        if let nsec = nsec {
                            VStack {
                                Text(nsec)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(20)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 24)
                            
                            Button(action: copyKey) {
                                HStack {
                                    Image(systemName: copiedPrivateKey ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copiedPrivateKey ? "Copied!" : "Copy to Clipboard")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            copiedPrivateKey ? Color.green : Color.orange,
                                            copiedPrivateKey ? Color.green.opacity(0.8) : Color.orange.opacity(0.8)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 24)
                        } else {
                            ProgressView("Loading private key...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .foregroundColor(Color.white.opacity(0.6))
                                .padding()
                        }
                    }
                }
            
            Spacer()
            
                // Confirmation
                Toggle(isOn: $savedKey) {
                    Text("I have saved my private key")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                }
                .toggleStyle(DarkCheckboxToggleStyle())
                .padding(.horizontal, 24)
                
                Button(action: continueToWallet) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Enter the Nutsack")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                savedKey ? Color.orange : Color.gray,
                                savedKey ? Color(red: 0.9, green: 0.5, blue: 0.1) : Color.gray.opacity(0.8)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: savedKey ? Color.orange.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 4)
                }
                .disabled(!savedKey)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Backup Key")
        .platformNavigationBarTitleDisplayMode(inline: true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadPrivateKey()
        }
    }
    
    private func loadPrivateKey() {
        Task {
            do {
                if let signer = nostrManager.authManager.activeSigner as? NDKPrivateKeySigner {
                    let privateKeyHex = signer.privateKeyValue
                    let nsecString = try signer.nsec
                    
                    await MainActor.run {
                        privateKey = privateKeyHex
                        nsec = nsecString
                    }
                }
            } catch {
                print("Failed to load private key: \(error)")
            }
        }
    }
    
    private func copyKey() {
        guard let nsec = nsec else { return }
        
        nsec.copyToPasteboard()
        withAnimation {
            copiedPrivateKey = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedPrivateKey = false
            }
        }
    }
    
    private func continueToWallet() {
        // Since the user is now authenticated via NDKAuthManager,
        // ensure state is stable before dismissing to prevent "Welcome Back" screen
        Task {
            // Brief delay to ensure auth state propagation
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                if let onComplete = onComplete {
                    onComplete()
                } else {
                    dismiss()
                }
            }
        }
    }
}

// Dark checkbox toggle style
struct DarkCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(configuration.isOn ? Color.orange : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(configuration.isOn ? Color.orange : Color.white.opacity(0.3), lineWidth: 2)
                )
                .frame(width: 24, height: 24)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            configuration.label
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                configuration.isOn.toggle()
            }
        }
    }
}