import Foundation

/// Main signature verification sampler that handles sampling logic and evil relay detection
public actor NDKSignatureVerificationSampler {
    /// Configuration for signature verification
    private let config: NDKSignatureVerificationConfig

    /// Cache for verified signatures
    private let cache: NDKSignatureVerificationCache

    /// Blocklisted relay URLs
    private var blocklistedRelays: Set<String> = []

    /// Delegate for signature verification events
    public weak var delegate: NDKSignatureVerificationDelegate?

    /// Tracer for telemetry (set lazily to avoid initialization order issues)
    private var tracer: NDKTracer?

    /// Statistics tracking
    private var totalVerifications: Int = 0
    private var failedVerifications: Int = 0

    public init(config: NDKSignatureVerificationConfig) {
        self.config = config
        cache = NDKSignatureVerificationCache()
    }

    /// Set tracer for telemetry
    public func setTracer(_ tracer: NDKTracer) {
        self.tracer = tracer
    }

    /// Verify an event's signature with sampling
    /// - Parameters:
    ///   - event: The event to verify
    ///   - relay: The relay that provided the event
    ///   - stats: The relay's signature statistics
    /// - Returns: The verification result
    public func verifyEvent(_ event: NDKEvent, from relay: RelayProtocol, stats: inout NDKRelaySignatureStats) async -> NDKSignatureVerificationResult {
        let eventId = event.id
        let signature = event.sig

        // Start telemetry span
        let span = tracer?.startSpan(name: "signature.verification", category: .signatureVerification)
        span?.set(SpanAttributes.eventId, eventId)
        span?.set(SpanAttributes.relayUrl, relay.url)
        span?.set(SpanAttributes.verificationSampleRatio, stats.currentValidationRatio)
        defer { span?.end() }

        guard !eventId.isEmpty, !signature.isEmpty else {
            span?.set(SpanAttributes.decisionOutcome, "invalid_empty")
            span?.setStatus(.error("Empty event ID or signature"))
            return .invalid
        }

        // Check if relay is blocklisted
        if blocklistedRelays.contains(relay.url) {
            span?.set(SpanAttributes.decisionOutcome, "relay_blocklisted")
            span?.setStatus(.error("Relay is blocklisted"))
            return .invalid
        }

        // Check cache first
        if await cache.isVerified(eventId: eventId, signature: signature) {
            span?.set(SpanAttributes.cacheHit, true)
            span?.set(SpanAttributes.decisionOutcome, "cached")
            span?.success()
            stats.addValidatedEvent()
            return .cached
        }
        span?.set(SpanAttributes.cacheHit, false)

        // Determine if we should verify based on sampling
        let shouldVerify = shouldVerifyEvent(relay: relay, stats: stats)
        span?.set(SpanAttributes.verificationSampled, shouldVerify)

        if !shouldVerify {
            // Skip verification due to sampling
            span?.set(SpanAttributes.decisionOutcome, "skipped_sampling")
            span?.set(SpanAttributes.decisionReason, "Below sample ratio threshold")
            span?.success()
            stats.addNonValidatedEvent()
            updateValidationRatio(relay: relay, stats: &stats)
            return .skipped
        }

        // Perform actual signature verification
        let verifySpan = tracer?.startSpan(name: "signature.verify", category: .signatureVerification, parent: span?.context)
        let isValid = await verifySignature(event: event)
        verifySpan?.set(SpanAttributes.verificationValid, isValid)

        if isValid {
            verifySpan?.success()
            verifySpan?.end()
            span?.set(SpanAttributes.verificationValid, true)
            span?.set(SpanAttributes.decisionOutcome, "valid")
            span?.success()

            // Cache the verified signature
            await cache.addVerifiedSignature(eventId: eventId, signature: signature)
            stats.addValidatedEvent()
            updateValidationRatio(relay: relay, stats: &stats)
            totalVerifications += 1
            return .valid
        } else {
            verifySpan?.setStatus(.error("Invalid signature"))
            verifySpan?.end()
            span?.set(SpanAttributes.verificationValid, false)
            span?.set(SpanAttributes.decisionOutcome, "invalid_signature")
            span?.addEvent("evil_relay_detected", attributes: [
                SpanAttributes.relayUrl: .string(relay.url),
                SpanAttributes.eventId: .string(eventId)
            ])
            span?.setStatus(.error("Invalid signature - evil relay detected"))

            // Invalid signature detected - this relay is evil!
            failedVerifications += 1
            await handleInvalidSignature(event: event, relay: relay)
            return .invalid
        }
    }

    /// Check if a relay is blocklisted
    public func isBlocklisted(relay: RelayProtocol) -> Bool {
        return blocklistedRelays.contains(relay.url)
    }

    /// Get blocklisted relay URLs
    public func getBlocklistedRelays() -> Set<String> {
        return blocklistedRelays
    }

    /// Clear the signature cache
    public func clearCache() async {
        await cache.clear()
    }

    /// Get verification statistics
    public func getStats() -> (totalVerifications: Int, failedVerifications: Int, blocklistedRelays: Int) {
        return (totalVerifications, failedVerifications, blocklistedRelays.count)
    }

    /// Set the signature verification delegate
    public func setDelegate(_ delegate: NDKSignatureVerificationDelegate?) {
        self.delegate = delegate
    }

    /// Quick check if event was already verified (fast path)
    /// - Parameter eventId: The event ID to check
    /// - Returns: true if the event has been verified previously
    public func isEventVerified(_ eventId: EventID) async -> Bool {
        return await cache.hasVerifiedEvent(eventId: eventId)
    }

    // MARK: - Private Methods

    /// Determine if we should verify an event based on sampling
    private func shouldVerifyEvent(relay _: RelayProtocol, stats: NDKRelaySignatureStats) -> Bool {
        // If verification is disabled for this relay, skip
        if !stats.verificationEnabled {
            return false
        }

        // Use effective ratio (per-relay target if set, otherwise current)
        let ratio = stats.effectiveValidationRatio

        // Always verify if ratio is 1.0
        if ratio >= 1.0 {
            return true
        }

        // Otherwise, randomly decide based on ratio
        return Double.random(in: 0 ..< 1) < ratio
    }

    /// Update the validation ratio for a relay
    private func updateValidationRatio(relay: RelayProtocol, stats: inout NDKRelaySignatureStats) {
        let newRatio: Double

        if let customFunction = config.validationRatioFunction {
            // Use custom function if provided
            newRatio = customFunction(relay, stats.validatedCount, stats.nonValidatedCount)
        } else {
            // Use default exponential decay function
            newRatio = calculateDefaultValidationRatio(
                validatedCount: stats.validatedCount,
                initialRatio: config.initialValidationRatio,
                lowestRatio: config.lowestValidationRatio
            )
        }

        stats.updateValidationRatio(newRatio)
    }

    /// Default validation ratio calculation with exponential decay
    private func calculateDefaultValidationRatio(validatedCount: Int, initialRatio: Double, lowestRatio: Double) -> Double {
        // Start with full validation for the first 10 events
        if validatedCount < 10 {
            return initialRatio
        }

        // Exponential decay: ratio = initial * e^(-0.01 * validatedCount)
        // This gradually decreases the ratio as more events are successfully validated
        let decayFactor = 0.01
        let newRatio = initialRatio * exp(-decayFactor * Double(validatedCount))

        // Never go below the minimum ratio
        return max(newRatio, lowestRatio)
    }

    /// Verify the actual signature
    private func verifySignature(event: NDKEvent) async -> Bool {
        let eventId = event.id
        let signature = event.sig

        guard !eventId.isEmpty, !signature.isEmpty else {
            return false
        }

        do {
            // Generate the expected event ID using the event's own method
            let calculatedId = try event.calculateID()

            // Verify the ID matches
            guard eventId == calculatedId else {
                return false
            }

            // Verify the signature
            let messageData = Data(hexString: eventId) ?? Data()
            return try Crypto.verify(signature: signature, message: messageData, pubkey: event.pubkey)
        } catch {
            NDKLogger.log(.debug, category: .signature, "Signature verification failed for event \(event.id): \(error)")
            return false
        }
    }

    /// Handle an invalid signature detection
    private func handleInvalidSignature(event: NDKEvent, relay: RelayProtocol) async {
        // A single invalid signature means the relay is evil
        NDKLogger.log(.error, category: .security, "⚠️ EVIL RELAY DETECTED: \(relay.url) provided event \(event.id) with invalid signature")

        // Notify delegate on main thread
        let delegateCopy = delegate
        await MainActor.run {
            delegateCopy?.signatureVerificationFailed(for: event, from: relay)
        }

        // Blocklist the relay if configured
        if config.autoBlocklistInvalidRelays {
            blocklistedRelays.insert(relay.url)

            // Notify delegate about blocklisting
            let delegateCopy = delegate
            await MainActor.run {
                delegateCopy?.relayBlocklisted(relay)
            }

            // Disconnect from the relay
            Task {
                await relay.disconnect()
            }
        }
    }

    /// Check if a relay is blocklisted
    public func isRelayBlocklisted(_ relayUrl: String) -> Bool {
        return blocklistedRelays.contains(relayUrl)
    }
}
