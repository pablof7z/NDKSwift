import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var ndk: NDK?
    @State private var sparkWalletManager: SparkWalletManager?
    @State private var isInitialized = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    ProgressView("Connecting...")
                        .task {
                            await initializeNDK()
                        }
                } else if !authViewModel.isLoggedIn {
                    OnboardingView(authViewModel: authViewModel)
                } else if let ndk = ndk, let sparkWalletManager = sparkWalletManager {
                    MainTabView(ndk: ndk, sparkWalletManager: sparkWalletManager)
                        .environmentObject(authViewModel)
                }
            }
            .onChange(of: authViewModel.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    ndk?.signer = authViewModel.signer
                } else {
                    ndk?.signer = nil
                }
            }
        }
    }

    private func initializeNDK() async {
        let relayUrls = OlasConstants.defaultRelays
        let newNDK = NDK(relayUrls: relayUrls)

        // Initialize NostrDB cache
        let cachePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("olas_cache")
            .path

        do {
            let cache = try await NDKNostrDBCache(path: cachePath)
            newNDK.cache = cache
        } catch {
            print("Failed to initialize cache: \(error)")
        }

        // Restore session if available
        await authViewModel.restoreSession()

        // Set signer if logged in
        if authViewModel.isLoggedIn {
            newNDK.signer = authViewModel.signer
        }

        await newNDK.connect()

        // Initialize SparkWalletManager
        let walletManager = SparkWalletManager(ndk: newNDK)

        // Attempt to restore saved wallet
        await walletManager.restoreWalletIfExists()

        await MainActor.run {
            self.ndk = newNDK
            self.sparkWalletManager = walletManager
            self.isInitialized = true
        }
    }
}
