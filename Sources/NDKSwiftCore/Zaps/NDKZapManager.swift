import Foundation
import CryptoKit

/// Manages zapping functionality with decoupled protocol and payment handling
public actor NDKZapManager: ZapManaging {
    private let ndk: NDK
    private var zapProtocols: [ZapType: NDKZapProtocol] = [:]
    private var paymentProviders: [NDKPaymentProvider] = []
    private var fallbackHandlers: [ZapFallbackHandler] = []

    // Typealias for payment provider factory/selection logic
    public typealias PaymentProviderSelector = (PaymentRequest, String?) async throws -> NDKPaymentProvider?

    // Cache for recipient zap info (pubkey -> info)
    private var recipientInfoCache: [String: RecipientZapInfo] = [:]
    // Track in-flight fetches to prevent duplicate requests
    private var fetchTasks: [String: Task<RecipientZapInfo, Never>] = [:]

    public init(ndk: NDK) {
        self.ndk = ndk

        // Register default Lightning protocol
        // Nutzap protocol should be registered by NDKSwiftCashu
        zapProtocols[.lightning] = NDKLightningZapProtocol(ndk: ndk)
    }

    // MARK: - Protocol Management

    /// Register a zap protocol
    public func register(protocol zapProtocol: NDKZapProtocol) {
        zapProtocols[zapProtocol.type] = zapProtocol
    }

    // MARK: - Payment Provider Management

    /// Register a payment provider
    public func register(provider: NDKPaymentProvider) {
        paymentProviders.append(provider)
    }

    /// Get all registered payment providers
    public func getRegisteredProviders() -> [NDKPaymentProvider] {
        return paymentProviders
    }

    /// Remove a payment provider
    public func unregister(providerId: String) {
        paymentProviders.removeAll { $0.id == providerId }
    }

    /// Clear all providers
    public func clearProviders() {
        paymentProviders.removeAll()
    }

    // MARK: - Fallback Handler Management

    /// Register a fallback handler
    public func register(fallbackHandler: ZapFallbackHandler) {
        fallbackHandlers.append(fallbackHandler)
    }

    // MARK: - Recipient Info Management

    /// Fetch all zap-related info for a recipient in one go
    public func fetchRecipientZapInfo(for user: NDKUser, maxAge: TimeInterval = TimeConstants.day) async -> RecipientZapInfo {
        let pubkey = user.pubkey

        // Check cache first
        if let cached = recipientInfoCache[pubkey], cached.isFresh(maxAge: maxAge) {
            return cached
        }

        // Check if there's already a fetch in progress
        if let existingTask = fetchTasks[pubkey] {
            return await existingTask.value
        }

        // Create a new fetch task
        let task = Task<RecipientZapInfo, Never> {
            // Create a combined filter for all event types we need
            var filter = NDKFilter()
            filter.authors = [pubkey]
            filter.kinds = [
                EventKind.metadata,           // kind:0 - profile with lightning address
                EventKind.nutzapPreferences  // kind:10019 - nutzap preferences
            ]

            // Create data source and collect until EOSE
            let dataSource = NDKSubscription(
                ndk: ndk,
                filter: filter,
                maxAge: maxAge
            )

            // Collect all events with a reasonable timeout
            let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionLong)

            // Create RecipientZapInfo from fetched events
            let info = await RecipientZapInfo.from(
                pubkey: pubkey,
                events: events
            )

            // Cache the result
            recipientInfoCache[pubkey] = info

            // Clean up the task reference
            fetchTasks.removeValue(forKey: pubkey)

            return info
        }

        // Store the task to prevent duplicate fetches
        fetchTasks[pubkey] = task

        return await task.value
    }

    /// Clear cached recipient info
    public func clearRecipientCache(for pubkey: String? = nil) {
        if let pubkey = pubkey {
            recipientInfoCache.removeValue(forKey: pubkey)
            fetchTasks[pubkey]?.cancel()
            fetchTasks.removeValue(forKey: pubkey)
        } else {
            recipientInfoCache.removeAll()
            for task in fetchTasks.values {
                task.cancel()
            }
            fetchTasks.removeAll()
        }
    }

    // MARK: - Zapping

    /// Smart zap with automatic protocol and payment provider selection
    public func zap(
        event: NDKEvent? = nil,
        to recipient: NDKUser,
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil,
        preferredProvider: String? = nil
    ) async throws -> ZapResult {
        NDKLogger.log(.debug, category: .wallet, "// 1. Fetch all recipient info ONCE")
        // 1. Fetch all recipient info ONCE
        let recipientInfo = await fetchRecipientZapInfo(for: recipient)

        NDKLogger.log(.debug, category: .wallet, "// 2. Select zap protocol based on available options")
        // 2. Select zap protocol based on available options
        let zapProtocol = try selectZapProtocol(
            recipientInfo: recipientInfo,
            preferredType: preferredType
        )

        NDKLogger.log(.debug, category: .wallet, "// 3. Prepare the zap with pre-fetched info")
        // 3. Prepare the zap with pre-fetched info
        let prepared = try await zapProtocol.prepareZap(
            event: event,
            recipientInfo: recipientInfo,
            amountSats: amountSats,
            comment: comment
        )

        NDKLogger.log(.debug, category: .wallet, "// 3. Try to find a provider that can directly fulfill the request")
        // 3. Try to find a provider that can directly fulfill the request
        let provider: (any NDKPaymentProvider)?
        do {
            provider = try await selectPaymentProvider(
                for: prepared.paymentRequest,
                preferredId: preferredProvider
            )
        } catch {
            NDKLogger.log(.warning, category: .wallet, "Failed to select payment provider for direct zap: \(error.localizedDescription)")
            provider = nil
        }

        if let provider = provider {
            NDKLogger.log(.debug, category: .wallet, "// Direct fulfillment path")
            // Direct fulfillment path
            let confirmation = try await provider.fulfill(prepared.paymentRequest)
            return try await zapProtocol.completeZap(
                prepared: prepared,
                confirmation: confirmation
            )
        }

        NDKLogger.log(.debug, category: .wallet, "// 4. No direct provider - trying fallback handlers")

        // 4. Try fallback handlers
        for handler in fallbackHandlers {
            if let result = try await handler.tryFallback(
                manager: self,
                protocol: zapProtocol,
                prepared: prepared,
                preferredProvider: preferredProvider
            ) {
                return result
            }
        }

        throw ZapError.noWalletConfigured
    }

    /// Get available payment providers for a given payment request
    public func availableProviders(for request: PaymentRequest) async -> [NDKPaymentProvider] {
        var available: [NDKPaymentProvider] = []

        for provider in paymentProviders {
            let isAvailable = await provider.isAvailable()
            let canFulfill = await provider.canFulfill(request)
            if isAvailable && canFulfill {
                available.append(provider)
            }
        }

        return available
    }

    /// Select the best payment provider for a request
    public func selectPaymentProvider(
        for request: PaymentRequest,
        preferredId: String?
    ) async throws -> NDKPaymentProvider {
        // Try preferred provider first
        if let preferredId = preferredId,
           let provider = paymentProviders.first(where: { $0.id == preferredId }) {
            let isAvailable = await provider.isAvailable()
            let canFulfill = await provider.canFulfill(request)
            if isAvailable && canFulfill {
                return provider
            }
        }

        // Find first available provider that can fulfill the request
        for provider in paymentProviders {
            let isAvailable = await provider.isAvailable()
            let canFulfill = await provider.canFulfill(request)
            if isAvailable && canFulfill {
                return provider
            }
        }

        throw ZapError.noWalletConfigured
    }

    /// Subscribe to zaps for an event or user (reactive, event-driven approach)
    public func subscribeToZaps(
        for event: NDKEvent? = nil,
        user: NDKUser? = nil
    ) -> AsyncThrowingStream<ZapInfo, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var kinds = [EventKind.zapReceipt]
                    // We need to know if we should listen for Nutzaps (kind 9321)
                    kinds.append(9321) // nutzap kind

                    var filter = NDKFilter()
                    filter.kinds = kinds

                    if let event = event {
                        let eventId = event.id
                        filter.addTagFilter("e", values: [eventId])
                    } else if let user = user {
                        filter.addTagFilter("p", values: [user.pubkey])
                    } else {
                        continuation.finish(throwing: NDKError.missingRequired("event or user"))
                        return
                    }

                    // Use NDKSubscription for real-time zap monitoring
                    let dataSource = NDKSubscription(
                        ndk: ndk,
                        filter: filter,
                        maxAge: 0, // Always fresh for real-time zap monitoring
                        cachePolicy: .cacheWithNetwork
                    )

                    for await event in dataSource.events {
                        let eventKind = event.kind
                        if eventKind == EventKind.zapReceipt {
                            let receipt = NDKZapReceipt(event: event)
                            do {
                                if let zapInfo = try await self.validateAndParseZapReceipt(receipt) {
                                    continuation.yield(zapInfo)
                                }
                            } catch {
                                NDKLogger.log(.warning, category: .wallet, "Failed to validate zap receipt \(receipt.event.id): \(error.localizedDescription)")
                            }
                        } else if eventKind == 9321 { // nutzap
                            // In Core we might not have full NDKNutzap model if it depends on CashuSwift.
                            // But we can parse basic info.

                            let recipientPubkey = event.tags.first(where: { $0.first == "p" })?[safe: 1] ?? ""
                            // amount is tag "amount"
                            let amountStr = event.tags.first(where: { $0.first == "amount" })?[safe: 1] ?? "0"
                            let totalAmount = Int64(amountStr) ?? 0

                            let zapInfo = ZapInfo(
                                type: .nutzap,
                                amountSats: totalAmount,
                                sender: event.pubkey,
                                recipient: recipientPubkey,
                                comment: event.content,
                                timestamp: Date(nostrTimestamp: event.createdAt),
                                event: event
                            )
                            continuation.yield(zapInfo)
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }


    // MARK: - Private Methods

    private func selectZapProtocol(
        recipientInfo: RecipientZapInfo,
        preferredType: ZapType?
    ) throws -> NDKZapProtocol {
        NDKLogger.log(.debug, category: .wallet, "selectZapProtocol \(String(describing: preferredType)), supported: \(recipientInfo.supportedZapTypes)")

        // Try preferred type first if it's supported
        if let preferredType = preferredType,
           recipientInfo.supports(preferredType),
           let zapProtocol = zapProtocols[preferredType] {
            return zapProtocol
        }

        // Smart routing: Prioritize Nutzap for privacy
        // But only if we have the protocol registered!
        if recipientInfo.hasNutzapSupport,
           let nutzapProtocol = zapProtocols[.nutzap] {
            return nutzapProtocol
        }

        // Fallback to Lightning
        if recipientInfo.hasLightningSupport,
           let lightningProtocol = zapProtocols[.lightning] {
            return lightningProtocol
        }
        NDKLogger.log(.debug, category: .wallet, "recipientDoesNotSupportZaps")

        throw ZapError.recipientDoesNotSupportZaps
    }

    private func validateAndParseZapReceipt(_ receipt: NDKZapReceipt) async throws -> ZapInfo? {
        // Get the recipient to fetch their LNURL provider pubkey
        guard let recipientPubkey = receipt.recipientPubkey,
              HexValidator.isValid32ByteHex(recipientPubkey) else {
            return nil
        }

        // Try to get provider pubkey from recipient's profile
        var providerPubkey: String?
        for await profile in await ndk.profileManager.subscribe(for: recipientPubkey, maxAge: TimeConstants.hour) {
            if let profile = profile {
                // Try to resolve LNURL to get provider pubkey
                if let lnurlAddress = profile.lud16 ?? profile.lud06 {
                    do {
                        let resolution = try await ndk.lnurlResolver.resolve(lnurlAddress)
                        providerPubkey = resolution.providerPubkey

                        // If no provider pubkey from LNURL, check if service allows Nostr
                        if providerPubkey == nil && resolution.payResponse.allowsNostr == true {
                            // Some services that allow Nostr might use the recipient's pubkey
                            // as the zap receipt signer
                            providerPubkey = receipt.event.pubkey
                        }
                    } catch {
                        NDKLogger.log(.warning, category: .general,
                                    "Failed to resolve LNURL for \(lnurlAddress): \(error)")
                        // Fall back to using receipt pubkey
                        providerPubkey = receipt.event.pubkey
                    }
                } else {
                    // No LNURL configured, use receipt pubkey
                    providerPubkey = receipt.event.pubkey
                }
            }
            break // Only need first value
        }

        guard let providerPubkey = providerPubkey,
              receipt.validate(lnurlProviderPubkey: providerPubkey) else {
            return nil
        }

        let amountSats = receipt.amountSats ?? 0
        let senderPubkey = receipt.senderPubkey
        let comment = receipt.comment
        let createdAt = receipt.event.createdAt

        return ZapInfo(
            type: .lightning,
            amountSats: amountSats,
            sender: senderPubkey,
            recipient: recipientPubkey,
            comment: comment,
            timestamp: Date(nostrTimestamp: createdAt),
            event: receipt.event
        )
    }
}

/// Information about a zap
public struct ZapInfo {
    public let type: ZapType
    public let amountSats: Int64
    public let sender: String?
    public let recipient: String
    public let comment: String?
    public let timestamp: Date
    public let event: NDKEvent
}

// MARK: - Removed objc_associatedObject pattern
// ZapManager is now a lazy property on NDK class for cleaner Swift-native dependency injection

// MARK: - User Extension

extension NDKUser {
    /// Zap this user
    public func zap(
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil,
        preferredProvider: String? = nil
    ) async throws -> ZapResult {
        return try await ndk.zapManager.zap(
            event: nil,
            to: self,
            amountSats: amountSats,
            comment: comment,
            preferredType: preferredType,
            preferredProvider: preferredProvider
        )
    }
}

// MARK: - Event Extension

extension NDKEvent {
    /// Zap this event (requires NDK instance)
    public func zap(
        with ndk: NDK,
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil,
        preferredProvider: String? = nil
    ) async throws -> ZapResult {
        guard let author = ndk.getUser(pubkey) else {
            throw NDKError.invalidDataFormat("pubkey", details: "Invalid event author pubkey")
        }

        return try await ndk.zapManager.zap(
            event: self,
            to: author,
            amountSats: amountSats,
            comment: comment,
            preferredType: preferredType,
            preferredProvider: preferredProvider
        )
    }
}
