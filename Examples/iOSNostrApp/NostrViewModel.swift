import Foundation
import SwiftUI
import NDKSwift
import Combine

@MainActor
class NostrViewModel: ObservableObject {
    @Published var nsec: String = ""
    @Published var npub: String = ""
    @Published var pubkey: String = ""
    @Published var isPublishing: Bool = false
    @Published var statusMessage: String = ""
    @Published var isError: Bool = false
    @Published var isConnectedViaBunker: Bool = false
    @Published var isBunkerConnecting: Bool = false
    @Published var showingAuthUrl: Bool = false
    @Published var authUrl: String = ""
    @Published var connectedRelays: [RelayInfo] = []
    @Published var showingAddRelay = false
    @Published var accountCreated = false
    
    private var ndk: NDK?
    private var signer: NDKSigner?
    private var bunkerSigner: NDKBunkerSigner?
    private let defaultRelays = [
        "wss://relay.primal.net",
        "wss://relay.damus.io",
        "wss://nos.lol"
    ]
    private var authUrlCancellable: AnyCancellable?
    
    // Timer for updating relay status
    private var relayUpdateTimer: Timer?
    
    init() {
        setupNDK()
        startRelayMonitoring()
    }
    
    deinit {
        relayUpdateTimer?.invalidate()
    }
    
    private func setupNDK() {
        ndk = NDK()
    }
    
    func createAccount() {
        Task {
            await MainActor.run {
                statusMessage = "Creating account..."
                isError = false
            }
            
            do {
                // Create signer with new keys
                let privateKeySigner = try NDKPrivateKeySigner.generate()
                signer = privateKeySigner
                
                // Set signer on NDK
                ndk?.signer = signer
                
                // Get keys in bech32 format
                let nsecValue = try privateKeySigner.nsec
                let npubValue = try privateKeySigner.npub
                let pubkeyValue = try await privateKeySigner.pubkey
                
                await MainActor.run {
                    nsec = nsecValue
                    npub = npubValue
                    pubkey = pubkeyValue
                    isConnectedViaBunker = false
                    statusMessage = "Account created successfully!"
                    isError = false
                    accountCreated = true
                }
                
                // Connect to relays
                await connectToRelays()
                
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to create account: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    func loginWithNsec(_ nsecString: String) {
        guard !nsecString.isEmpty else {
            statusMessage = "Please enter a valid nsec"
            isError = true
            return
        }
        
        // Validate nsec format
        guard nsecString.hasPrefix("nsec1") else {
            statusMessage = "Invalid nsec format. Must start with 'nsec1'"
            isError = true
            return
        }
        
        Task {
            await MainActor.run {
                statusMessage = "Processing login..."
                isError = false
            }
            
            do {
                // Create private key signer from nsec
                let privateKeySigner = try NDKPrivateKeySigner(nsec: nsecString)
                signer = privateKeySigner
                
                // Set signer on NDK
                ndk?.signer = signer
                
                // Get keys in bech32 format
                let nsecValue = try privateKeySigner.nsec
                let npubValue = try privateKeySigner.npub
                let pubkeyValue = try await privateKeySigner.pubkey
                
                await MainActor.run {
                    nsec = nsecString  // Use the original input nsec instead of re-encoding
                    npub = npubValue
                    pubkey = pubkeyValue
                    isConnectedViaBunker = false
                    statusMessage = "Logged in successfully!"
                    isError = false
                }
                
                // Connect to relays
                await connectToRelays()
                
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to login with nsec: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    private func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        do {
            // Add default relays
            for relayUrl in defaultRelays {
                try await ndk.addRelay(relayUrl)
            }
            
            // Connect to relays
            try await ndk.connect()
            
            await MainActor.run {
                statusMessage = "Connected to relays"
                isError = false
                updateRelayStatus()
            }
        } catch {
            await MainActor.run {
                statusMessage = "Failed to connect: \(error.localizedDescription)"
                isError = true
            }
        }
    }
    
    func connectWithBunker(_ bunkerUrl: String) {
        guard let ndk = ndk else { return }
        
        isBunkerConnecting = true
        statusMessage = "Connecting to bunker..."
        isError = false
        
        Task {
            do {
                // Create bunker signer
                let bunker = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerUrl)
                self.bunkerSigner = bunker
                
                // Listen for auth URLs
                authUrlCancellable = await bunker.authUrlPublisher.sink { [weak self] authUrl in
                    Task { @MainActor in
                        self?.authUrl = authUrl
                        self?.showingAuthUrl = true
                    }
                }
                
                // Connect to bunker
                let user = try await bunker.connect()
                
                // Set as signer
                ndk.signer = bunker
                self.signer = bunker
                
                // Get public key
                npub = user.npub
                pubkey = user.pubkey
                
                await MainActor.run {
                    isConnectedViaBunker = true
                    isBunkerConnecting = false
                    statusMessage = "Connected via bunker!"
                    isError = false
                }
                
                // Connect to relays
                await connectToRelays()
                
            } catch {
                await MainActor.run {
                    isBunkerConnecting = false
                    statusMessage = "Bunker connection failed: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    func publishMessage(_ content: String) {
        guard !content.isEmpty, let ndk = ndk else { return }
        
        Task {
            await MainActor.run {
                isPublishing = true
                statusMessage = ""
            }
            
            do {
                // Create text note event (kind 1)
                let event = NDKEvent(content: content)
                event.ndk = ndk  // Set the NDK instance
                
                // Sign and publish
                try await event.sign()
                
                // Log raw event to console
                let rawEventData = event.rawEvent()
                print("Publishing raw event:", rawEventData)
                
                try await ndk.publish(event)
                
                // Get the nevent1 encoding of the event (including relay info)
                let nevent = try event.encode(includeRelays: true)
                
                await MainActor.run {
                    isPublishing = false
                    statusMessage = "Message published successfully!\nEvent ID: \(nevent)"
                    isError = false
                }
            } catch {
                await MainActor.run {
                    isPublishing = false
                    statusMessage = "Failed to publish: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    // MARK: - Relay Management
    
    private func startRelayMonitoring() {
        relayUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRelayStatus()
            }
        }
    }
    
    private func updateRelayStatus() {
        guard let ndk = ndk else {
            connectedRelays = []
            return
        }
        
        connectedRelays = ndk.relays.map { relay in
            RelayInfo(
                url: relay.url,
                connectionState: relay.connectionState,
                connectedAt: relay.stats.connectedAt,
                messagesSent: relay.stats.messagesSent,
                messagesReceived: relay.stats.messagesReceived
            )
        }
    }
    
    func addRelay(_ url: String) {
        guard let ndk = ndk, !url.isEmpty else { return }
        
        Task {
            do {
                try await ndk.addRelay(url)
                
                await MainActor.run {
                    statusMessage = "Relay added: \(url)"
                    isError = false
                    updateRelayStatus()
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to add relay: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    func removeRelay(_ url: String) {
        guard let ndk = ndk else { return }
        
        ndk.removeRelay(url)
        updateRelayStatus()
        statusMessage = "Relay removed: \(url)"
        isError = false
    }
}

// MARK: - Relay Info Model

struct RelayInfo: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let connectionState: NDKRelayConnectionState
    let connectedAt: Date?
    let messagesSent: Int
    let messagesReceived: Int
    
    var statusText: String {
        switch connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting..."
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
    
    var statusColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .connecting, .disconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .failed:
            return .red
        }
    }
}

// Helper extension for hex conversion
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
    
    var bytes: [UInt8] {
        return Array(self)
    }
}