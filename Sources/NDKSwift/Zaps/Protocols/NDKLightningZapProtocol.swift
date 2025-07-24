import Foundation

/// LNURL Pay endpoint response
struct LNURLPayEndpoint: Codable {
    let callback: String
    let maxSendable: Int64
    let minSendable: Int64
    let metadata: String
    let tag: String
    let allowsNostr: Bool?
    let nostrPubkey: String?
    
    var domain: String? {
        guard let url = URL(string: callback) else { return nil }
        return url.host
    }
    
    var supportsZaps: Bool {
        return allowsNostr == true && nostrPubkey != nil
    }
}

/// NIP-57 Lightning Zap protocol implementation
public class NDKLightningZapProtocol: NDKZapProtocol {
    public let type = ZapType.lightning
    
    private let ndk: NDK
    private let urlSession: URLSession
    
    public init(ndk: NDK, urlSession: URLSession = .shared) {
        self.ndk = ndk
        self.urlSession = urlSession
    }
    
    public func canZap(recipientInfo: RecipientZapInfo) -> Bool {
        // Simply check the pre-fetched info
        return recipientInfo.hasLightningSupport
    }
    
    public func prepareZap(
        event: NDKEvent?,
        recipientInfo: RecipientZapInfo,
        amountSats: Int64,
        comment: String?
    ) async throws -> PreparedZap {
        // Create NDKUser from recipient info
        let user = NDKUser(pubkey: recipientInfo.pubkey)
        
        // 1. Resolve LNURL endpoint using pre-fetched profile
        guard let lightningAddress = recipientInfo.lightningAddress else {
            throw ZapError.recipientDoesNotSupportZaps
        }
        
        let endpoint = try await resolveLNURL(address: lightningAddress)
        
        guard endpoint.supportsZaps else {
            throw ZapError.endpointDoesNotSupportZaps
        }
        
        // 2. Validate amount
        let amountMillisats = PaymentConstants.satsToMillisats(amountSats)
        guard amountMillisats >= endpoint.minSendable,
              amountMillisats <= endpoint.maxSendable else {
            throw ZapError.amountOutOfRange(
                min: PaymentConstants.millisatsToSats(endpoint.minSendable),
                max: PaymentConstants.millisatsToSats(endpoint.maxSendable)
            )
        }
        
        // 3. Use NDK's connected relays
        let recipientRelays = await ndk.connectedRelays().map { $0.url }
        
        // 4. Create zap request event
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            signer: ndk.signer!,
            recipient: user,
            amountMillisats: amountMillisats,
            comment: comment,
            relays: recipientRelays,
            zappedEvent: event
        )
        
        // 5. Fetch invoice from LNURL endpoint
        let invoice = try await fetchInvoice(
            endpoint: endpoint,
            zapRequest: zapRequest,
            amountMillisats: amountMillisats
        )
        
        // 6. Create payment request
        let paymentRequest = LightningInvoiceRequest(
            invoice: invoice,
            amountSats: amountSats,
            recipient: recipientInfo.pubkey
        )
        
        // 7. Store metadata for completion
        let metadata: [String: Any] = [
            "zapRequest": zapRequest,
            "endpoint": endpoint,
            "relays": recipientRelays
        ]
        
        return PreparedZap(
            paymentRequest: paymentRequest,
            recipient: user,
            zappedEvent: event,
            comment: comment,
            metadata: metadata
        )
    }
    
    public func completeZap(
        prepared: PreparedZap,
        confirmation: PaymentConfirmation
    ) async throws -> ZapResult {
        // Extract metadata
        guard let zapRequest = prepared.metadata["zapRequest"] as? NDKZapRequest,
              let endpoint = prepared.metadata["endpoint"] as? LNURLPayEndpoint else {
            throw NDKError.missingRequired("zapRequest and endpoint", in: "metadata")
        }
        
        // For Lightning zaps, the payment confirmation doesn't directly create the zap receipt
        // The LNURL server will publish the receipt when it sees the payment
        
        // Wait for zap receipt (kind: 9735) from the LNURL provider
        let receiptEvent = try await waitForZapReceipt(
            for: prepared.recipient,
            zappedEvent: prepared.zappedEvent,
            zapRequestId: zapRequest.event.id,
            providerPubkey: endpoint.nostrPubkey,
            timeout: PaymentConstants.zapReceiptTimeout
        )
        
        // Return result with the actual receipt
        return ZapResult(
            type: .lightning,
            amountSats: prepared.paymentRequest.amountSats,
            receiptEvent: receiptEvent,
            nutzapEvent: nil
        )
    }
    
    // MARK: - Private Methods
    
    private func waitForZapReceipt(
        for recipient: NDKUser,
        zappedEvent: NDKEvent?,
        zapRequestId: String?,
        providerPubkey: String?,
        timeout: TimeInterval
    ) async throws -> NDKEvent? {
        // Create filter for zap receipts
        var filter = NDKFilter()
        filter.kinds = [EventKind.zapReceipt]
        filter.addTagFilter("p", values: [recipient.pubkey])
        
        if let zappedEvent = zappedEvent {
            let eventId = zappedEvent.id
            filter.addTagFilter("e", values: [eventId])
        }
        
        // Use NDKDataSource for real-time zap receipt monitoring
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for real-time monitoring
            cachePolicy: .networkOnly // Skip cache for zap receipts
        )
        
        // Create timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * TimeConstants.nanosecondsPerSecond)
            throw ZapError.timeoutWaitingForReceipt
        }
        
        for await event in dataSource.events {
            let receipt = NDKZapReceipt(event: event)
            
            // Check if this receipt matches our zap request
            let receiptZapRequestId = receipt.zapRequestId
            if let zapRequestId = zapRequestId,
               receiptZapRequestId == zapRequestId {
                // Validate the receipt if we have provider pubkey
                if let providerPubkey = providerPubkey {
                    let isValid = receipt.validate(lnurlProviderPubkey: providerPubkey)
                    if isValid {
                        timeoutTask.cancel()
                        return event
                    }
                } else {
                    // No provider pubkey to validate against, accept the receipt
                    timeoutTask.cancel()
                    return event
                }
            }
        }
        
        return nil
    }
    
    private func resolveLNURL(for user: NDKUser) async throws -> LNURLPayEndpoint {
        var userProfile: NDKUserProfile?
        
        for await profile in await ndk.profileManager.observe(for: user.pubkey, maxAge: TimeConstants.hour) {
            userProfile = profile
            break // Only need first value
        }
        
        guard let profile = userProfile else {
            throw ZapError.noLNURL
        }
        
        let lnurlString = profile.lud16 ?? profile.lud06
        guard let lnurlString = lnurlString else {
            throw ZapError.noLNURL
        }
        
        return try await resolveLNURL(address: lnurlString)
    }
    
    private func resolveLNURL(address lnurlString: String) async throws -> LNURLPayEndpoint {
        
        // Convert Lightning address to URL if needed
        let url: URL
        if lnurlString.contains("@") {
            // Lightning address format
            let parts = lnurlString.split(separator: "@")
            guard parts.count == 2 else {
                throw ZapError.invalidLNURL("Invalid lightning address format")
            }
            let username = String(parts[0])
            let domain = String(parts[1])
            guard let lnurlURL = URL(string: "https://\(domain)\(WellKnownPath.lnurlp)\(username)") else {
                throw ZapError.invalidLNURL("Failed to construct LNURL")
            }
            url = lnurlURL
        } else if lnurlString.lowercased().starts(with: Bech32HRP.lnurl) {
            // Decode bech32 LNURL
            do {
                let decoded = try Bech32.decode(lnurlString)
                guard decoded.hrp == Bech32HRP.lnurl else {
                    throw ZapError.invalidLNURL("Invalid LNURL bech32 format")
                }
                
                // Convert data to string
                let data = Data(decoded.data)
                guard let decodedString = String(data: data, encoding: .utf8),
                      let lnurlURL = URL(string: decodedString) else {
                    throw ZapError.invalidLNURL("Invalid LNURL data")
                }
                url = lnurlURL
            } catch {
                throw ZapError.invalidLNURL("Failed to decode LNURL: \(error.localizedDescription)")
            }
        } else {
            // Assume it's already a URL
            guard let lnurlURL = URL(string: lnurlString) else {
                throw ZapError.invalidLNURL("Invalid URL")
            }
            url = lnurlURL
        }
        
        // Fetch LNURL metadata
        var request = URLRequest(url: url)
        request.httpMethod = HTTPConstants.methodGet
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ZapError.invalidLNURL("Failed to fetch LNURL metadata")
        }
        
        // Parse response
        struct LNURLResponse: Codable {
            let callback: String
            let minSendable: Int64?
            let maxSendable: Int64?
            let allowsNostr: Bool?
            let nostrPubkey: String?
            let commentAllowed: Int?
            let metadata: String?
            let tag: String?
        }
        
        let lnurlResponse = try JSONCoding.decode(LNURLResponse.self, from: data)
        
        guard let callbackURL = URL(string: lnurlResponse.callback) else {
            throw ZapError.invalidLNURL("Invalid callback URL")
        }
        
        return LNURLPayEndpoint(
            callback: callbackURL.absoluteString,
            maxSendable: lnurlResponse.maxSendable ?? 100_000_000_000,
            minSendable: lnurlResponse.minSendable ?? 1000,
            metadata: lnurlResponse.metadata ?? "",
            tag: lnurlResponse.tag ?? "payRequest",
            allowsNostr: lnurlResponse.allowsNostr ?? false,
            nostrPubkey: lnurlResponse.nostrPubkey
        )
    }
    
    private func fetchInvoice(
        endpoint: LNURLPayEndpoint,
        zapRequest: NDKZapRequest,
        amountMillisats: Int64
    ) async throws -> String {
        // Encode zap request as JSON
        let zapRequestJSON = try zapRequest.encodeForCallback()
        
        // Build callback URL with parameters
        var components = URLComponents(url: URL(string: endpoint.callback)!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "amount", value: String(amountMillisats)),
            URLQueryItem(name: "nostr", value: zapRequestJSON)
        ]
        
        if let lnurl = zapRequest.lnurl {
            components.queryItems?.append(URLQueryItem(name: "lnurl", value: lnurl))
        }
        
        guard let url = components.url else {
            throw ZapError.invoiceFetchFailed("Failed to construct callback URL")
        }
        
        // Fetch invoice
        var request = URLRequest(url: url)
        request.httpMethod = HTTPConstants.methodGet
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ZapError.invoiceFetchFailed("HTTP error")
        }
        
        // Parse response
        struct InvoiceResponse: Codable {
            let pr: String  // Payment request (invoice)
        }
        
        let invoiceResponse = try JSONCoding.decode(InvoiceResponse.self, from: data)
        return invoiceResponse.pr
    }
    
    private func getRecipientRelays(_ recipient: NDKUser) async throws -> [String] {
        // Try to get relay list from NIP-65
        var relayListFilter = NDKFilter()
        relayListFilter.authors = [recipient.pubkey]
        relayListFilter.kinds = [EventKind.relayList]
        
        // Use NDKDataSource for fetching relay list
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: relayListFilter,
            maxAge: TimeConstants.hour // 1 hour - relay lists don't change frequently
        )
        
        // Collect all relay list events and use the most recent
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionMedium)
        if let relayListEvent = events.mostRecent {
            let eventTags = relayListEvent.tags
            let relays = eventTags.tagValues(named: NostrTagConstants.TagName.reference)
            
            if !relays.isEmpty {
                return relays
            }
        }
        
        // Fallback to connected relays
        let connected = await ndk.pool.connectedRelays()
        return connected.map { $0.url }
    }
}

// MARK: - Safe Array Access

// Array extension removed - already defined elsewhere