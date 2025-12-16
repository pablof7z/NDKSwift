import NDKSwift
import NDKSwiftNostrDB
import SwiftUI

/// Test view to verify search functionality with nostrdb
struct SearchTestView: View {
    @State private var ndk: NDK?
    @State private var status: String = "Initializing..."
    @State private var cacheType: String = "Unknown"
    @State private var isNostrDBAvailable: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Search Functionality Test")
                .font(.title)
                .padding()

            VStack(alignment: .leading, spacing: 8) {
                Text("Status: \(status)")
                Text("Cache Type: \(cacheType)")
                Text("NostrDB Available: \(isNostrDBAvailable ? "✅ Yes" : "❌ No")")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)

            if let ndk = ndk {
                NDKUISearchableFeedView(
                    ndk: ndk,
                    filter: NDKFilter(kinds: [1], limit: 20)
                )
            } else {
                ProgressView("Setting up NDK with NostrDB cache...")
            }
        }
        .task {
            await setupNDKWithNostrDB()
        }
    }

    private func setupNDKWithNostrDB() async {
        do {
            status = "Creating NostrDB cache..."

            // Create nostrdb cache (in-memory for testing)
            let cache = try await NDKNostrDBCache(path: nil)

            status = "Creating NDK with NostrDB cache..."

            // Create NDK with nostrdb cache
            let keypair = NDKKeypair.generate()
            let signer = NDKKeypairSigner(keypair: keypair)

            ndk = NDK(
                signer: signer,
                cache: cache
            )

            // Verify cache type
            if let ndk = ndk {
                cacheType = String(describing: type(of: ndk.cache))

                // Check if search will be available (synchronous check now)
                let searchDS = NDKSearchDataSource(ndk: ndk)
                isNostrDBAvailable = searchDS.isNostrDBAvailable

                print("🔍 Cache type: \(cacheType)")
                print("🔍 Is NDKNostrDBCache: \(ndk.cache is NDKNostrDBCache)")
                print("🔍 Search available: \(isNostrDBAvailable)")

                status = isNostrDBAvailable ? "✅ Ready! Search bar should appear below." : "❌ NostrDB not detected"
            }

        } catch {
            status = "❌ Error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SearchTestView()
}
