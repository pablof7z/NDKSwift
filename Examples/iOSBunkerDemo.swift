import SwiftUI
import NDKSwift

// Standalone iOS demo showing NIP-46 bunker login
struct iOSBunkerDemoApp: App {
    var body: some Scene {
        WindowGroup {
            BunkerDemoView()
        }
    }
}

struct BunkerDemoView: View {
    @StateObject private var viewModel = BunkerViewModel()
    @State private var bunkerUrl = ""
    @State private var messageText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if !viewModel.isConnected {
                    // Login View
                    VStack(spacing: 20) {
                        Text("NIP-46 Bunker Demo")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Connect with your bunker")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        TextField("bunker://...", text: $bunkerUrl)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: {
                            viewModel.connectWithBunker(bunkerUrl)
                        }) {
                            Text("Connect")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.purple)
                                .cornerRadius(10)
                        }
                        .disabled(bunkerUrl.isEmpty || viewModel.isConnecting)
                        
                        if viewModel.isConnecting {
                            HStack {
                                ProgressView()
                                Text("Connecting...")
                            }
                        }
                        
                        // Pre-fill with test bunker URL
                        Button("Use Test Bunker") {
                            bunkerUrl = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.nsec.app&secret=VpESbyIFohMA"
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding()
                } else {
                    // Connected View
                    VStack(spacing: 20) {
                        Text("Connected via Bunker")
                            .font(.headline)
                            .foregroundColor(.purple)
                        
                        Text("Public Key: \(viewModel.npub)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Divider()
                        
                        // Message composer
                        VStack(alignment: .leading) {
                            Text("Send a message:")
                                .font(.headline)
                            
                            TextField("Hello Nostr!", text: $messageText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button(action: {
                                viewModel.publishMessage(messageText)
                                messageText = ""
                            }) {
                                Text("Publish")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            .disabled(messageText.isEmpty || viewModel.isPublishing)
                        }
                        
                        if viewModel.isPublishing {
                            ProgressView("Publishing...")
                        }
                        
                        if !viewModel.statusMessage.isEmpty {
                            Text(viewModel.statusMessage)
                                .font(.caption)
                                .foregroundColor(viewModel.isError ? .red : .green)
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Bunker Demo")
            .alert("Authorization Required", isPresented: $viewModel.showingAuthUrl) {
                Button("Open in Browser") {
                    #if os(iOS)
                    if let url = URL(string: viewModel.authUrl) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }
                Button("Copy URL") {
                    #if os(iOS)
                    UIPasteboard.general.string = viewModel.authUrl
                    #endif
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please authorize this connection:\n\n\(viewModel.authUrl)")
            }
        }
    }
}

@MainActor
class BunkerViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var npub = ""
    @Published var isPublishing = false
    @Published var statusMessage = ""
    @Published var isError = false
    @Published var showingAuthUrl = false
    @Published var authUrl = ""
    
    private var ndk: NDK?
    private var bunkerSigner: NDKBunkerSigner?
    
    init() {
        ndk = NDK(relayUrls: ["wss://relay.nsec.app", "wss://relay.damus.io"])
    }
    
    func connectWithBunker(_ bunkerUrl: String) {
        guard let ndk = ndk else { return }
        
        isConnecting = true
        statusMessage = ""
        
        Task {
            do {
                // Connect to relays first
                try await ndk.connect()
                
                // Create bunker signer
                let bunker = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerUrl)
                self.bunkerSigner = bunker
                
                // Listen for auth URLs
                Task {
                    for await authUrl in await bunker.authUrlPublisher.values {
                        await MainActor.run {
                            self.authUrl = authUrl
                            self.showingAuthUrl = true
                        }
                    }
                }
                
                // Connect to bunker
                let user = try await bunker.connect()
                
                // Set as signer
                ndk.signer = bunker
                
                // Get public key
                let pubkey = user.pubkey
                npub = try Bech32.encode(hrp: "npub", data: Data(hex: pubkey)!.bytes)
                
                await MainActor.run {
                    isConnected = true
                    isConnecting = false
                    statusMessage = "Connected!"
                    isError = false
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    statusMessage = "Error: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    func publishMessage(_ content: String) {
        guard let ndk = ndk, !content.isEmpty else { return }
        
        Task {
            await MainActor.run {
                isPublishing = true
            }
            
            do {
                // Create event
                let event = NDKEvent(content: content)
                event.ndk = ndk
                
                // Sign and publish
                try await event.sign()
                let result = try await ndk.publish(event)
                
                await MainActor.run {
                    isPublishing = false
                    statusMessage = "Published! Event ID: \(event.id ?? "?")"
                    isError = false
                }
            } catch {
                await MainActor.run {
                    isPublishing = false
                    statusMessage = "Failed: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
}

// Helper for hex conversion
extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// Preview
struct BunkerDemoView_Previews: PreviewProvider {
    static var previews: some View {
        BunkerDemoView()
    }
}