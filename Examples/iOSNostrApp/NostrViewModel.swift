import Foundation
import NDKSwift
import Combine

@MainActor
class NostrViewModel: ObservableObject {
    @Published var nsec: String = ""
    @Published var npub: String = ""
    @Published var isPublishing: Bool = false
    @Published var statusMessage: String = ""
    @Published var isError: Bool = false
    
    private var ndk: NDK?
    private var signer: NDKPrivateKeySigner?
    private let relay = "wss://relay.primal.net"
    
    init() {
        setupNDK()
    }
    
    private func setupNDK() {
        ndk = NDK()
    }
    
    func createAccount() {
        do {
            // Create signer with new keys
            signer = try NDKPrivateKeySigner.generate()
            
            // Set signer on NDK
            ndk?.signer = signer
            
            // Get keys in bech32 format
            if let signer = signer {
                nsec = try signer.nsec
                npub = try signer.npub
            }
        } catch {
            statusMessage = "Failed to create account: \(error.localizedDescription)"
            isError = true
        }
        
        // Connect to relay
        Task {
            await connectToRelay()
        }
    }
    
    private func connectToRelay() async {
        guard let ndk = ndk else { return }
        
        do {
            // Add relay
            try await ndk.addRelay(relay)
            
            // Connect to relays
            try await ndk.connect()
            
            await MainActor.run {
                statusMessage = "Connected to relay"
                isError = false
            }
        } catch {
            await MainActor.run {
                statusMessage = "Failed to connect: \(error.localizedDescription)"
                isError = true
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
                try await ndk.publish(event)
                
                await MainActor.run {
                    isPublishing = false
                    statusMessage = "Message published successfully!"
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