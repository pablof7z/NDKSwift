import Foundation

/// Represents a NIP-60 Cashu wallet
public class NDKCashuWallet: NDKWallet {
    private let ndk: NDK
    private let walletId: String

    /// Mint URLs this wallet uses
    public private(set) var mints: Set<String> = []

    /// Current balance in satoshis
    public private(set) var balance: Int64 = 0

    public init(ndk: NDK, walletId: String = UUID().uuidString) {
        self.ndk = ndk
        self.walletId = walletId
    }

    // MARK: - NDKWallet Protocol

    public func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation {
        // Check balance
        guard balance >= request.amount else {
            throw NDKError.insufficientBalance
        }

        // Get recipient's mint preferences
        let recipientMints = try await getRecipientMints(request.recipient)

        // Find a common mint
        let commonMints = mints.intersection(recipientMints)
        guard let selectedMint = commonMints.first else {
            throw NDKError.paymentFailed("No common mint found with recipient")
        }

        // Create nutzap
        var nutzap = NDKNutzap(ndk: ndk)
        nutzap.mint = selectedMint
        nutzap.setRecipient(request.recipient.pubkey)
        nutzap.comment = request.comment

        // In a real implementation, this would:
        // 1. Use CashuSwift to create proofs
        // 2. Lock them with P2PK if supported
        // 3. Deduct from wallet balance

        // For now, create mock proofs
        nutzap.proofs = [
            CashuProof(
                id: "mock-keyset",
                amount: Int(request.amount),
                secret: "mock-secret",
                C: "mock-signature"
            ),
        ]

        // Sign and publish nutzap
        try await nutzap.sign()

        // Get recipient's preferred relays
        let relays = try await getRecipientRelays(request.recipient)
        let relaySet = NDKRelaySet(relayURLs: relays, ndk: ndk)

        try await nutzap.publish(on: relaySet)

        // Update balance
        balance -= request.amount

        return NDKCashuPaymentConfirmation(
            amount: request.amount,
            recipient: request.recipient.pubkey,
            timestamp: Date(),
            nutzap: nutzap
        )
    }

    public func getBalance() async throws -> Int64 {
        // In a real implementation, this would:
        // 1. Load proofs from NIP-60 events
        // 2. Check their spent status with mints
        // 3. Calculate total balance
        return balance
    }

    public func createInvoice(amount _: Int64, description _: String?) async throws -> String {
        // This would create a Lightning invoice via mint
        throw NDKError.notImplemented
    }

    public func supports(method: NDKPaymentMethod) -> Bool {
        return method == .nutzap
    }

    // MARK: - NIP-60 Event Management

    /// Save wallet state as NIP-60 events
    public func save() async throws {
        // Create wallet event (kind 7375)
        let walletEvent = NDKEvent(content: "", tags: [])
        walletEvent.ndk = ndk
        walletEvent.kind = EventKind.cashuWallet
        walletEvent.content = try JSONEncoder().encode(WalletData(
            name: "NDKSwift Wallet",
            mints: Array(mints),
            balance: balance
        )).base64EncodedString()

        // Add wallet ID tag
        walletEvent.tags.append(["d", walletId])

        // Sign and publish
        try await walletEvent.sign()
        _ = try await ndk.publish(walletEvent)
    }

    /// Load wallet state from NIP-60 events
    public func load() async throws {
        let filter = try NDKFilter(
            authors: [await ndk.signer!.pubkey],
            kinds: [EventKind.cashuWallet],
            tags: ["d": Set([walletId])]
        )

        if let walletEvent = try await ndk.fetchEvent(filter) {
            // Decrypt and parse wallet data
            if let data = Data(base64Encoded: walletEvent.content),
               let walletData = try? JSONDecoder().decode(WalletData.self, from: data)
            {
                self.mints = Set(walletData.mints)
                self.balance = walletData.balance
            }
        }
    }

    // MARK: - Helper Methods

    private func getRecipientMints(_ recipient: NDKUser) async throws -> Set<String> {
        let filter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [EventKind.cashuMintList]
        )

        if let mintListEvent = try await ndk.fetchEvent(filter),
           let mintList = NDKCashuMintList.from(mintListEvent)
        {
            return Set(mintList.mints)
        }

        return []
    }

    private func getRecipientRelays(_ recipient: NDKUser) async throws -> [String] {
        // Try to get from mint list first
        let mintListFilter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [EventKind.cashuMintList]
        )

        if let mintListEvent = try await ndk.fetchEvent(mintListFilter),
           let mintList = NDKCashuMintList.from(mintListEvent)
        {
            let relays = mintList.relays
            if !relays.isEmpty {
                return relays
            }
        }

        // Fallback to relay list (NIP-65)
        let relayListFilter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [EventKind.relayList]
        )

        if let relayListEvent = try await ndk.fetchEvent(relayListFilter) {
            return relayListEvent.tags
                .filter { $0.first == "r" }
                .compactMap { $0[safe: 1] }
        }

        // Fallback to connected relays
        return ndk.pool.connectedRelays().map { $0.url }
    }
}

// MARK: - Supporting Types

private struct WalletData: Codable {
    let name: String
    let mints: [String]
    let balance: Int64
}

/// Relay set for publishing events
public struct NDKRelaySet {
    let relayURLs: [String]
    let ndk: NDK

    public init(relayURLs: [String], ndk: NDK) {
        self.relayURLs = relayURLs
        self.ndk = ndk
    }
}
