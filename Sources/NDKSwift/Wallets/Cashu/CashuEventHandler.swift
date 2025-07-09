import Foundation

/// Handles NIP-60 event creation and parsing
actor CashuEventHandler {
    // MARK: - Properties
    
    private let ndk: NDK
    private let walletId: String
    
    // MARK: - Initialization
    
    init(ndk: NDK, walletId: String) {
        self.ndk = ndk
        self.walletId = walletId
    }
    
    // MARK: - Wallet Events (Kind 7375)
    
    /// Create a wallet metadata event
    func createWalletEvent(walletData: WalletData) async throws -> NDKEvent {
        // Serialize wallet data
        let encoder = JSONEncoder()
        let walletJSON = try encoder.encode(walletData)
        
        // Encrypt using NIP-44
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        let user = NDKUser(pubkey: userPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: user,
            value: String(data: walletJSON, encoding: .utf8)!,
            scheme: .nip44
        )
        
        // Create event
        let event = NDKEvent(
            pubkey: userPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.cashuWallet,
            tags: [["d", walletId]],
            content: encryptedContent
        )
        
        // Set NDK and sign
        await event.setNDK(ndk)
        try await event.sign()
        
        return event
    }
    
    /// Parse a wallet metadata event
    func parseWalletEvent(_ event: NDKEvent) async throws -> WalletData {
        // Decrypt content
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        let user = NDKUser(pubkey: userPubkey)
        let eventContent = await event.content
        let decrypted = try await signer.decrypt(
            sender: user,
            value: eventContent,
            scheme: .nip44
        )
        
        // Parse JSON
        guard let data = decrypted.data(using: String.Encoding.utf8) else {
            throw EventError.invalidContent
        }
        
        return try JSONDecoder().decode(WalletData.self, from: data)
    }
    
    // MARK: - Token Events (Kind 7376)
    
    /// Create a token storage event
    func createTokenEvent(token: CashuToken, mint: String) async throws -> NDKEvent {
        // Serialize token
        let encoder = JSONEncoder()
        let tokenJSON = try encoder.encode(token)
        
        // Encrypt using NIP-44
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        let user = NDKUser(pubkey: userPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: user,
            value: String(data: tokenJSON, encoding: .utf8)!,
            scheme: .nip44
        )
        
        // Create event
        let event = NDKEvent(
            pubkey: userPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.cashuToken,
            tags: [
                ["d", UUID().uuidString],
                ["mint", mint],
                ["wallet", walletId]
            ],
            content: encryptedContent
        )
        
        // Set NDK and sign
        await event.setNDK(ndk)
        try await event.sign()
        
        return event
    }
    
    /// Parse a token storage event
    func parseTokenEvent(_ event: NDKEvent) async throws -> CashuToken {
        // Decrypt content
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        let user = NDKUser(pubkey: userPubkey)
        let eventContent = await event.content
        let decrypted = try await signer.decrypt(
            sender: user,
            value: eventContent,
            scheme: .nip44
        )
        
        // Parse JSON
        guard let data = decrypted.data(using: String.Encoding.utf8) else {
            throw EventError.invalidContent
        }
        
        return try JSONDecoder().decode(CashuToken.self, from: data)
    }
    
    // MARK: - Mint List Events (Kind 10019)
    
    /// Create a public mint list event
    func createMintListEvent(mints: [String], p2pkPubkey: String?) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        
        // Build tags
        var tags: [Tag] = []
        
        // Add mint tags
        for mint in mints {
            tags.append(["mint", mint])
        }
        
        // Add P2PK pubkey if available
        if let pubkey = p2pkPubkey {
            tags.append(["pubkey", pubkey])
        }
        
        // Create event
        let event = NDKEvent(
            pubkey: userPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.cashuMintList,
            tags: tags,
            content: ""
        )
        
        // Set NDK and sign
        await event.setNDK(ndk)
        try await event.sign()
        
        return event
    }
    
    /// Parse a mint list event
    func parseMintListEvent(_ event: NDKEvent) async -> (mints: [String], p2pkPubkey: String?) {
        var mints: [String] = []
        var p2pkPubkey: String?
        
        let eventTags = await event.tags
        for tag in eventTags {
            if tag.count >= 2 {
                switch tag[0] {
                case "mint":
                    mints.append(tag[1])
                case "pubkey":
                    p2pkPubkey = tag[1]
                default:
                    break
                }
            }
        }
        
        return (mints, p2pkPubkey)
    }
    
    // MARK: - P2PK Key Backup
    
    /// Create encrypted P2PK key backup event
    func createP2PKBackupEvent(privateKey: String) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        let user = NDKUser(pubkey: userPubkey)
        
        // Encrypt private key
        let encryptedContent = try await signer.encrypt(
            recipient: user,
            value: privateKey,
            scheme: .nip44
        )
        
        // Create event
        let event = NDKEvent(
            pubkey: userPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.cashuWallet,
            tags: [
                ["d", "\(walletId)-p2pk"],
                ["type", "p2pk-backup"]
            ],
            content: encryptedContent
        )
        
        // Set NDK and sign
        await event.setNDK(ndk)
        try await event.sign()
        
        return event
    }
    
    /// Parse P2PK key backup event
    func parseP2PKBackupEvent(_ event: NDKEvent) async throws -> String {
        // Decrypt content
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        let userPubkey = try await signer.pubkey
        let user = NDKUser(pubkey: userPubkey)
        let eventContent = await event.content
        return try await signer.decrypt(
            sender: user,
            value: eventContent,
            scheme: .nip44
        )
    }
}

// MARK: - Errors

enum EventError: LocalizedError {
    case invalidContent
    case encryptionFailed
    case decryptionFailed
    case signingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "Invalid event content"
        case .encryptionFailed:
            return "Failed to encrypt event"
        case .decryptionFailed:
            return "Failed to decrypt event"
        case .signingFailed:
            return "Failed to sign event"
        }
    }
}