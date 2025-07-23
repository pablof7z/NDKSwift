import Foundation

/// Builder for creating NWC request events (kind 23194)
public struct NWCRequestBuilder {
    private let ndk: NDK
    private let walletPubkey: String
    private let signer: NDKSigner
    
    public init(ndk: NDK, walletPubkey: String, signer: NDKSigner) {
        self.ndk = ndk
        self.walletPubkey = walletPubkey
        self.signer = signer
    }
    
    /// Build a NWC request event
    public func buildRequest<T: Encodable>(method: String, params: T) async throws -> NDKEvent {
        // Create the request envelope
        let envelope = NWCRequestEnvelope(method: method, params: params)
        
        // Encode to JSON with snake_case keys
        let jsonString = try JSONCoding.encodeSnakeCaseToString(envelope)
        
        // Get signer pubkey
        let signerPubkey = try await signer.pubkey
        
        // Encrypt content using NIP-04
        let walletUser = NDKUser(pubkey: walletPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: walletUser,
            value: jsonString,
            scheme: .nip04
        )
        
        // Create the event using the builder
        let event = try await NDKEventBuilder(ndk: ndk)
            .pubkey(signerPubkey)
            .createdAt(Timestamp.now)
            .kind(.nostrWalletConnectReq)
            .content(encryptedContent)
            .tag(["p", walletPubkey])
            .build(signer: signer)
        
        return event
    }
    
    // MARK: - Convenience methods for specific requests
    
    public func buildPayInvoiceRequest(_ request: PayInvoiceRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.payInvoice.rawValue, params: request)
    }
    
    public func buildMultiPayInvoiceRequest(_ request: MultiPayInvoiceRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.multiPayInvoice.rawValue, params: request)
    }
    
    public func buildPayKeysendRequest(_ request: PayKeysendRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.payKeysend.rawValue, params: request)
    }
    
    public func buildMultiPayKeysendRequest(_ request: MultiPayKeysendRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.multiPayKeysend.rawValue, params: request)
    }
    
    public func buildMakeInvoiceRequest(_ request: MakeInvoiceRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.makeInvoice.rawValue, params: request)
    }
    
    public func buildLookupInvoiceRequest(_ request: LookupInvoiceRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.lookupInvoice.rawValue, params: request)
    }
    
    public func buildListTransactionsRequest(_ request: ListTransactionsRequest) async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.listTransactions.rawValue, params: request)
    }
    
    public func buildGetBalanceRequest() async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.getBalance.rawValue, params: GetBalanceRequest())
    }
    
    public func buildGetInfoRequest() async throws -> NDKEvent {
        return try await buildRequest(method: NWCMethod.getInfo.rawValue, params: GetInfoRequest())
    }
}

// MARK: - Event Kind Extension

extension Int {
    /// NWC request event kind (23194)
    public static let nostrWalletConnectReq = 23194
    
    /// NWC response event kind (23195)
    public static let nostrWalletConnectRes = 23195
    
    /// NWC notification event kind (23196)
    public static let nostrWalletConnectNotification = 23196
    
    /// NWC info event kind (13194)
    public static let nostrWalletConnectInfo = 13194
}
