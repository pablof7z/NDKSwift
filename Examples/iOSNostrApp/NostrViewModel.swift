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
    @Published var lastPublishedEvent: NDKEvent?
    @Published var publishedEventRelayStatuses: [(relay: String, status: String, okMessage: String?)] = []
    
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
        // Set up file cache for persistent storage and queued events
        do {
            let cache = try NDKFileCache(path: "NostrCache")
            ndk = NDK(cacheAdapter: cache)
        } catch {
            print("[ViewModel] Failed to create file cache: \(error)")
            ndk = NDK()
        }
        ndk?.debugMode = true // Enable debug mode to see queued event messages
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
        
        // Add default relays but don't connect yet
        for relayUrl in defaultRelays {
            _ = ndk.addRelay(relayUrl)
        }
        
        await MainActor.run {
            statusMessage = "Relays added. Use Connect button to connect."
            isError = false
            updateRelayStatus()
        }
    }
    
    func connectWithBunker(_ bunkerUrl: String) {
        guard let ndk = ndk else {
            print("[ViewModel] ERROR: NDK not initialized")
            return
        }
        
        print("[ViewModel] Starting bunker connection with URL: \(bunkerUrl)")
        
        isBunkerConnecting = true
        statusMessage = "Connecting to bunker..."
        isError = false
        
        Task {
            do {
                // Create bunker signer
                print("[ViewModel] Creating bunker signer...")
                let bunker = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerUrl)
                self.bunkerSigner = bunker
                
                // Listen for auth URLs
                print("[ViewModel] Setting up auth URL listener...")
                authUrlCancellable = await bunker.authUrlPublisher.sink { [weak self] authUrl in
                    print("[ViewModel] Received auth URL: \(authUrl)")
                    Task { @MainActor in
                        self?.authUrl = authUrl
                        self?.showingAuthUrl = true
                    }
                }
                
                // Connect to bunker
                print("[ViewModel] Attempting to connect to bunker...")
                let user = try await bunker.connect()
                print("[ViewModel] Successfully connected! User pubkey: \(user.pubkey)")
                
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
                print("[ViewModel] Connecting to relays for normal operations...")
                await connectToRelays()
                
            } catch {
                print("[ViewModel] Bunker connection failed: \(error)")
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
                publishedEventRelayStatuses = []
            }
            
            do {
                // Create text note event (kind 1)
                let event = NDKEvent(content: content)
                event.ndk = ndk  // Set the NDK instance
                
                // Sign the event
                try await event.sign()
                
                // Store the event for tracking
                await MainActor.run {
                    lastPublishedEvent = event
                }
                
                // Log raw event to console
                let rawEventData = event.rawEvent()
                print("Publishing raw event:", rawEventData)
                
                // Publish the event
                let publishedRelays = try await ndk.publish(event)
                
                // Update relay statuses
                await MainActor.run {
                    isPublishing = false
                    updatePublishStatuses(for: event)
                    
                    let totalRelays = ndk.relays.count
                    let queuedRelays = totalRelays - publishedRelays.count
                    
                    if publishedRelays.isEmpty {
                        statusMessage = "Event created but not published to any relays. Will be published when relays connect."
                        isError = false // Not an error, just queued
                    } else if queuedRelays > 0 {
                        statusMessage = "Event published to \(publishedRelays.count) relay(s), queued for \(queuedRelays) disconnected relay(s)"
                        isError = false
                    } else {
                        statusMessage = "Event published to all \(publishedRelays.count) relay(s)"
                        isError = false
                    }
                }
                
                // Start monitoring for OK messages
                startMonitoringPublishStatus(for: event)
                
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
        
        _ = ndk.addRelay(url)
        
        statusMessage = "Relay added: \(url)"
        isError = false
        updateRelayStatus()
    }
    
    func removeRelay(_ url: String) {
        guard let ndk = ndk else { return }
        
        ndk.removeRelay(url)
        updateRelayStatus()
        statusMessage = "Relay removed: \(url)"
        isError = false
    }
    
    func connectRelay(_ url: String) {
        guard let ndk = ndk else { return }
        
        Task {
            do {
                // Find the relay
                if let relay = ndk.relays.first(where: { $0.url == url }) {
                    try await relay.connect()
                    
                    await MainActor.run {
                        statusMessage = "Connected to: \(url)"
                        isError = false
                        updateRelayStatus()
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to connect: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
    }
    
    func disconnectRelay(_ url: String) {
        guard let ndk = ndk else { return }
        
        Task {
            // Find the relay
            if let relay = ndk.relays.first(where: { $0.url == url }) {
                await relay.disconnect()
                
                await MainActor.run {
                    statusMessage = "Disconnected from: \(url)"
                    isError = false
                    updateRelayStatus()
                }
            }
        }
    }
    
    // MARK: - Publish Status Monitoring
    
    private func updatePublishStatuses(for event: NDKEvent) {
        var statuses: [(relay: String, status: String, okMessage: String?)] = []
        
        // Add all relays with their current status
        for relay in ndk?.relays ?? [] {
            let relayUrl = relay.url
            var statusText = ""
            var okMessage: String?
            
            // Check publish status
            if let publishStatus = event.relayPublishStatuses[relayUrl] {
                switch publishStatus {
                case .pending:
                    statusText = "⏳ Queued (waiting for connection)"
                case .succeeded:
                    statusText = "✅ Published"
                case .failed(let reason):
                    switch reason {
                    case .connectionFailed:
                        statusText = "❌ Not connected"
                    case .custom(let message):
                        statusText = "❌ \(message)"
                    default:
                        statusText = "❌ Failed"
                    }
                case .inProgress:
                    statusText = "🔄 Publishing..."
                case .rateLimited:
                    statusText = "⚠️ Rate limited"
                case .retrying(let attempt):
                    statusText = "🔁 Retrying (\(attempt))"
                }
            } else if relay.connectionState != .connected {
                statusText = "⚪ Not connected"
            } else {
                statusText = "⏳ Waiting..."
            }
            
            // Check for OK message
            if let ok = event.relayOKMessages[relayUrl] {
                if ok.accepted {
                    statusText = "✅ Accepted"
                } else {
                    statusText = "❌ Rejected"
                }
                okMessage = ok.message
            }
            
            statuses.append((relay: relayUrl, status: statusText, okMessage: okMessage))
        }
        
        publishedEventRelayStatuses = statuses
    }
    
    private func startMonitoringPublishStatus(for event: NDKEvent) {
        // Monitor for 10 seconds for OK messages
        Task {
            for _ in 0..<20 { // 20 * 0.5 = 10 seconds
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    if lastPublishedEvent?.id == event.id {
                        updatePublishStatuses(for: event)
                    }
                }
            }
        }
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