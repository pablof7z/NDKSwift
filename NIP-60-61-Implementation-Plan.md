# NIP-60/61 Implementation Plan for NDKSwift

## Overview
This document outlines the implementation plan for adding NIP-60 (Cashu Wallets) and NIP-61 (Nutzaps) support to NDKSwift using CashuSwift.

## Architecture Overview

### Core Components

1. **NDKCashuWallet** - Main wallet actor implementing the NDKWallet protocol
2. **Proof Management** - Handling Cashu proof states (available, reserved, spent)
3. **Event Management** - NIP-60 event creation, encryption, and parsing
4. **Nutzap Handler** - NIP-61 implementation for sending/receiving nutzaps
5. **P2PK Management** - Key management for Pay-to-Public-Key operations
6. **Mint Integration** - Managing connections to Cashu mints

### File Structure

```
Sources/NDKSwift/
├── Wallet/
│   └── NDKWallet.swift                    # Base protocol (existing)
└── Wallets/
    └── Cashu/
        ├── NDKCashuWallet.swift           # Main wallet actor
        ├── Types/
        │   ├── CashuTypes.swift           # Core Cashu types
        │   ├── NDKNutzap.swift            # Nutzap event model
        │   └── NDKCashuMintList.swift     # Mint list event model
        ├── Managers/
        │   ├── CashuProofManager.swift    # Proof state management
        │   ├── CashuEventHandler.swift    # NIP-60 event handling
        │   └── P2PKManager.swift          # P2PK key management
        ├── Handlers/
        │   ├── NutzapSender.swift         # Send nutzaps
        │   └── NutzapReceiver.swift       # Receive/monitor nutzaps
        └── Support/
            ├── CashuError.swift           # Error types
            └── CashuExtensions.swift      # Helper extensions
```

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)

#### 1.1 Set up project structure
- Create directory structure
- Add CashuSwift dependency to Package.swift
- Move existing NDKCashuWallet stub to new location

#### 1.2 Implement core types
```swift
// CashuTypes.swift
public struct CashuProof: Codable {
    let id: String          // Keyset ID
    let amount: Int
    let secret: String
    let C: String          // Signature
    var witness: String?   // For P2PK unlocking
    
    // State tracking (not serialized)
    var state: ProofState = .available
}

public enum ProofState {
    case available
    case reserved(until: Date, for: String)
    case spent
    case pending
}

public struct CashuToken: Codable {
    let token: [TokenEntry]
    let unit: String
    let memo: String?
}

public struct TokenEntry: Codable {
    let mint: String
    let proofs: [CashuProof]
}
```

#### 1.3 Convert NDKCashuWallet to Actor
```swift
public actor NDKCashuWallet: NDKWallet {
    private let ndk: NDK
    private let walletId: String
    private let proofManager: CashuProofManager
    private let eventHandler: CashuEventHandler
    private let p2pkManager: P2PKManager
    
    // Cached state
    private var mints: Set<CashuMint> = []
    private var balance: Int64 = 0
    private var isLoaded = false
    
    // CashuSwift connections
    private var mintConnections: [String: Mint] = [:]
    
    public init(ndk: NDK, walletId: String? = nil) {
        self.ndk = ndk
        self.walletId = walletId ?? UUID().uuidString
        self.proofManager = CashuProofManager()
        self.eventHandler = CashuEventHandler(ndk: ndk)
        self.p2pkManager = P2PKManager()
    }
}
```

### Phase 2: NIP-60 Event Management (Week 1-2)

#### 2.1 Implement wallet events
```swift
// Event kinds from NIP-60
extension EventKind {
    static let cashuWallet = EventKind(rawValue: 7375)      // Wallet metadata
    static let cashuToken = EventKind(rawValue: 7376)       // Token storage
    static let cashuProof = EventKind(rawValue: 7377)       // Individual proofs
    static let cashuMintList = EventKind(rawValue: 10019)   // Public mint list
}

// CashuEventHandler.swift
actor CashuEventHandler {
    func createWalletEvent(walletData: WalletData) async throws -> NDKEvent {
        var event = NDKEvent(ndk: ndk)
        event.kind = .cashuWallet
        event.tags = [["d", walletId]]
        
        // Encrypt wallet data using NIP-44
        let encrypted = try await ndk.encrypt(walletData.toJSON(), to: userPubkey)
        event.content = encrypted
        
        return event
    }
    
    func parseWalletEvent(_ event: NDKEvent) async throws -> WalletData {
        let decrypted = try await ndk.decrypt(event.content, from: event.pubkey)
        return try WalletData.fromJSON(decrypted)
    }
}
```

#### 2.2 Implement proof storage
```swift
extension CashuEventHandler {
    func saveProofs(_ proofs: [CashuProof], mint: String) async throws {
        // Create token for storage
        let token = CashuToken(
            token: [TokenEntry(mint: mint, proofs: proofs)],
            unit: "sat",
            memo: "Wallet backup"
        )
        
        // Create event
        var event = NDKEvent(ndk: ndk)
        event.kind = .cashuToken
        event.tags = [
            ["d", UUID().uuidString],
            ["mint", mint],
            ["wallet", walletId]
        ]
        
        // Encrypt token
        let encrypted = try await ndk.encrypt(token.toJSON(), to: userPubkey)
        event.content = encrypted
        
        // Sign and publish
        try await event.sign()
        try await ndk.publish(event)
    }
}
```

### Phase 3: Proof Management (Week 2)

#### 3.1 Implement CashuProofManager
```swift
actor CashuProofManager {
    private var proofs: [String: CashuProof] = [:]  // secret -> proof
    private var proofsByMint: [String: Set<String>] = [:]
    
    func addProofs(_ newProofs: [CashuProof], mint: String) {
        for proof in newProofs {
            proofs[proof.secret] = proof
            proofsByMint[mint, default: []].insert(proof.secret)
        }
    }
    
    func reserveProofs(amount: Int64, mint: String, for purpose: String) throws -> [CashuProof] {
        let available = getAvailableProofs(mint: mint)
        let selected = try selectProofs(from: available, amount: amount)
        
        // Mark as reserved
        let expiry = Date().addingTimeInterval(30) // 30 second reservation
        for proof in selected {
            proofs[proof.secret]?.state = .reserved(until: expiry, for: purpose)
        }
        
        return selected
    }
    
    func confirmSpent(secrets: [String]) {
        for secret in secrets {
            proofs[secret]?.state = .spent
        }
    }
    
    func releaseReservation(secrets: [String]) {
        for secret in secrets {
            if case .reserved = proofs[secret]?.state {
                proofs[secret]?.state = .available
            }
        }
    }
}
```

#### 3.2 Implement proof selection algorithm
```swift
extension CashuProofManager {
    private func selectProofs(from available: [CashuProof], amount: Int64) throws -> [CashuProof] {
        // Sort by amount descending
        let sorted = available.sorted { $0.amount > $1.amount }
        
        var selected: [CashuProof] = []
        var total = 0
        
        // Greedy selection
        for proof in sorted {
            if total >= amount { break }
            selected.append(proof)
            total += proof.amount
        }
        
        guard total >= amount else {
            throw CashuError.insufficientBalance
        }
        
        return selected
    }
}
```

### Phase 4: CashuSwift Integration (Week 2-3)

#### 4.1 Mint connection management
```swift
extension NDKCashuWallet {
    private func connectToMint(_ mintURL: String) async throws -> Mint {
        if let existing = mintConnections[mintURL] {
            return existing
        }
        
        let url = URL(string: mintURL)!
        let mint = try await CashuSwift.loadMint(url: url)
        mintConnections[mintURL] = mint
        
        return mint
    }
    
    private func disconnectFromMint(_ mintURL: String) {
        mintConnections.removeValue(forKey: mintURL)
    }
}
```

#### 4.2 Implement core wallet operations
```swift
extension NDKCashuWallet {
    public func getBalance() async throws -> Int64 {
        if !isLoaded {
            try await load()
        }
        
        // Calculate from available proofs
        let availableProofs = await proofManager.getAvailableProofs()
        return availableProofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    public func mintTokens(amount: Int64, mint mintURL: String) async throws {
        let mint = try await connectToMint(mintURL)
        
        // Request mint quote
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )
        let quote = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MintQuote
        
        // Generate outputs
        let (outputs, blindingFactors, secrets) = try CashuSwift.generateOutputs(
            distribution: splitIntoBase2(Int(amount)),
            mint: mint,
            seed: nil
        )
        
        // Issue tokens (would need Lightning payment in production)
        let (proofs, _) = try await CashuSwift.issue(
            for: quote,
            with: mint,
            seed: nil
        )
        
        // Store proofs
        await proofManager.addProofs(proofs.toNDKProofs(), mint: mintURL)
        
        // Save to Nostr
        try await eventHandler.saveProofs(proofs.toNDKProofs(), mint: mintURL)
    }
}
```

### Phase 5: NIP-61 Nutzap Implementation (Week 3)

#### 5.1 Implement P2PK manager
```swift
actor P2PKManager {
    private let keychain = KeychainManager(service: "NDKCashuWallet")
    private var keypair: (privateKey: String, publicKey: String)?
    
    func getOrCreateKeypair() async throws -> (privateKey: String, publicKey: String) {
        if let existing = keypair {
            return existing
        }
        
        // Check keychain
        if let stored = try? keychain.getP2PKPrivateKey() {
            let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: stored)
            let publicKey = privateKey.publicKey
            
            keypair = (
                privateKey: privateKey.dataRepresentation.hexEncodedString(),
                publicKey: publicKey.dataRepresentation.hexEncodedString()
            )
            return keypair!
        }
        
        // Generate new
        let privateKey = try secp256k1.Schnorr.PrivateKey()
        let publicKey = privateKey.publicKey
        
        // Store in keychain
        try keychain.storeP2PKPrivateKey(privateKey.dataRepresentation)
        
        keypair = (
            privateKey: privateKey.dataRepresentation.hexEncodedString(),
            publicKey: publicKey.dataRepresentation.hexEncodedString()
        )
        
        return keypair!
    }
    
    func getCashuPublicKey() async throws -> String {
        let (_, pubkey) = try await getOrCreateKeypair()
        return "02" + pubkey  // Cashu format
    }
}
```

#### 5.2 Implement nutzap sending
```swift
// NutzapSender.swift
extension NDKCashuWallet {
    public func sendNutzap(
        to recipient: NDKUser,
        amount: Int64,
        comment: String? = nil,
        relays: [String]? = nil
    ) async throws -> NDKNutzap {
        // Get recipient's mint preferences
        let recipientMints = try await getRecipientMints(recipient)
        
        // Find common mint
        let commonMints = mints.intersection(recipientMints)
        guard let selectedMint = commonMints.first else {
            throw CashuError.noCommonMint
        }
        
        // Get recipient's P2PK pubkey
        let recipientP2PK = try await getRecipientP2PKPubkey(recipient)
        
        // Reserve proofs
        let proofs = try await proofManager.reserveProofs(
            amount: amount,
            mint: selectedMint.url,
            for: "nutzap"
        )
        
        // Lock proofs with P2PK
        let mint = try await connectToMint(selectedMint.url)
        let cashuProofs = proofs.toCashuSwiftProofs()
        
        let (lockedToken, change, _) = try await CashuSwift.send(
            inputs: cashuProofs,
            mint: mint,
            amount: Int(amount),
            seed: nil,
            memo: comment,
            lockToPublicKey: recipientP2PK
        )
        
        // Create nutzap event
        var nutzap = NDKNutzap(ndk: ndk)
        nutzap.mint = selectedMint.url
        nutzap.proofs = lockedToken.toNDKProofs()
        nutzap.unit = "sat"
        nutzap.comment = comment
        nutzap.setRecipient(recipient.pubkey)
        
        // Add p tag for recipient
        nutzap.event.tags.append(["p", recipient.pubkey])
        
        // Sign and publish
        try await nutzap.sign()
        
        let relaySet = relays ?? (try await getRecipientRelays(recipient))
        try await ndk.publish(nutzap.event, to: relaySet)
        
        // Confirm proofs as spent
        await proofManager.confirmSpent(proofs.map { $0.secret })
        
        // Handle change
        if !change.isEmpty {
            await proofManager.addProofs(change.toNDKProofs(), mint: selectedMint.url)
        }
        
        return nutzap
    }
}
```

#### 5.3 Implement nutzap receiving
```swift
// NutzapReceiver.swift
extension NDKCashuWallet {
    public func startNutzapMonitor() async {
        let filter = NDKFilter(
            kinds: [.nutzap],
            tags: ["p": Set([ndk.activeUser.pubkey])]
        )
        
        for await event in ndk.subscribe(filter: filter) {
            Task {
                do {
                    try await processIncomingNutzap(event)
                } catch {
                    print("Failed to process nutzap: \(error)")
                }
            }
        }
    }
    
    private func processIncomingNutzap(_ event: NDKEvent) async throws {
        guard let nutzap = NDKNutzap.from(event) else { return }
        
        // Check if already processed
        if await isNutzapProcessed(event.id) { return }
        
        // Get our P2PK private key
        let (privateKey, _) = try await p2pkManager.getOrCreateKeypair()
        
        // Connect to mint
        let mint = try await connectToMint(nutzap.mint)
        
        // Create token from nutzap
        let token = CashuToken(
            token: [TokenEntry(mint: nutzap.mint, proofs: nutzap.proofs)],
            unit: nutzap.unit,
            memo: nutzap.comment
        )
        
        // Unlock proofs
        let (unlockedProofs, _, _) = try await CashuSwift.receive(
            token: token.toCashuSwiftToken(),
            of: mint,
            seed: nil,
            privateKey: privateKey
        )
        
        // Add to wallet
        await proofManager.addProofs(unlockedProofs.toNDKProofs(), mint: nutzap.mint)
        
        // Mark as processed
        await markNutzapProcessed(event.id)
        
        // Save proofs
        try await eventHandler.saveProofs(unlockedProofs.toNDKProofs(), mint: nutzap.mint)
        
        // Emit notification
        await emitNutzapReceived(nutzap, amount: unlockedProofs.reduce(0) { $0 + $1.amount })
    }
}
```

### Phase 6: Testing & Integration (Week 4)

#### 6.1 Unit Tests
- Test proof selection algorithm
- Test P2PK key generation and storage
- Test event encryption/decryption
- Test concurrent proof operations

#### 6.2 Integration Tests
```swift
class CashuWalletIntegrationTests: XCTestCase {
    let testMint = "https://nofees.testnut.cashu.space"
    
    func testMintingTokens() async throws {
        let ndk = NDK()
        let wallet = ndk.createCashuWallet()
        
        try await wallet.mintTokens(amount: 100, mint: testMint)
        
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 100)
    }
    
    func testSendingNutzap() async throws {
        // Setup two wallets
        let sender = createTestWallet()
        let recipient = createTestWallet()
        
        // Mint tokens to sender
        try await sender.mintTokens(amount: 100, mint: testMint)
        
        // Send nutzap
        let nutzap = try await sender.sendNutzap(
            to: recipient.user,
            amount: 50,
            comment: "Test nutzap"
        )
        
        // Verify balances
        XCTAssertEqual(try await sender.getBalance(), 50)
        
        // Process on recipient
        try await recipient.processIncomingNutzap(nutzap.event)
        XCTAssertEqual(try await recipient.getBalance(), 50)
    }
}
```

#### 6.3 Documentation
- API documentation for all public methods
- Integration guide for app developers
- Migration guide from existing wallets

## Key Considerations

### Security
- P2PK private keys stored in Keychain
- All wallet events encrypted with NIP-44
- Proof states managed atomically
- No logging of sensitive data

### Performance
- Proof operations batched where possible
- Mint connections cached
- Balance calculations optimized
- Concurrent operations properly isolated

### Error Handling
- Comprehensive error types
- Retry logic for network operations
- Graceful degradation
- Clear error messages

### Compatibility
- Support for multiple Cashu token versions
- Backwards compatibility with existing events
- Interoperability with other NIP-60 wallets
- Standard compliance verification

## Timeline Summary

- **Week 1**: Core infrastructure and types
- **Week 2**: Event management and proof handling
- **Week 3**: CashuSwift integration and nutzap implementation
- **Week 4**: Testing, documentation, and polish

## Success Criteria

1. ✅ Full NIP-60 compliance for wallet operations
2. ✅ Complete NIP-61 support for nutzaps
3. ✅ Thread-safe implementation using actors
4. ✅ Comprehensive test coverage
5. ✅ Performance on par with NWC implementation
6. ✅ Clear documentation and examples
7. ✅ Seamless integration with existing NDKSwift features