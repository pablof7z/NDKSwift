import Foundation
@testable import NDKSwift

/// Mock signer for testing
class MockSigner: NDKSigner {
    let privateKey: PrivateKey
    
    var pubkey: PublicKey {
        get async throws {
            return try Crypto.getPublicKey(from: privateKey)
        }
    }
    
    init(privateKey: PrivateKey) {
        self.privateKey = privateKey
    }
    
    func sign(_ event: NDKEvent) async throws -> Signature {
        // Sign the event ID
        let eventIdData = Data(hexString: event.id)!
        return try Crypto.sign(message: eventIdData, privateKey: privateKey)
    }
    
    func sign(event: inout NDKEvent) async throws {
        // Deprecated method - should not be used
        throw NDKError.notImplemented("Use NDKEventBuilder for creating and signing events")
    }
    
    func blockUntilReady() async throws {
        // Mock signer is always ready
    }
    
    func user() async throws -> NDKUser {
        let pubkey = try await self.pubkey
        return NDKUser(pubkey: pubkey)
    }
    
    func relays(ndk: NDK?) async -> [NDKRelay] {
        return []
    }
    
    func encryptionEnabled() async -> [NDKEncryptionScheme] {
        return [.nip04, .nip44]
    }
    
    func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            return try Crypto.nip04Encrypt(message: value, privateKey: privateKey, publicKey: recipient.pubkey)
        case .nip44:
            return try Crypto.nip44Encrypt(message: value, privateKey: privateKey, publicKey: recipient.pubkey)
        }
    }
    
    func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            return try Crypto.nip04Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
        case .nip44:
            return try Crypto.nip44Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
        }
    }
}

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}