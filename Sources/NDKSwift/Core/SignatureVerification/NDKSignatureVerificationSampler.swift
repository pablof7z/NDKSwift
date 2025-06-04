import Foundation

/// Main signature verification sampler that handles sampling logic and evil relay detection
public actor NDKSignatureVerificationSampler {
    /// Configuration for signature verification
    private let config: NDKSignatureVerificationConfig
    
    /// Cache for verified signatures
    private let cache: NDKSignatureVerificationCache
    
    /// Blacklisted relay URLs
    private var blacklistedRelays: Set<String> = []
    
    /// Delegate for signature verification events
    public weak var delegate: NDKSignatureVerificationDelegate?
    
    /// Statistics tracking
    private var totalVerifications: Int = 0
    private var failedVerifications: Int = 0
    
    public init(config: NDKSignatureVerificationConfig) {
        self.config = config
        self.cache = NDKSignatureVerificationCache()
    }
    
    /// Verify an event's signature with sampling
    /// - Parameters:
    ///   - event: The event to verify
    ///   - relay: The relay that provided the event
    ///   - stats: The relay's signature statistics
    /// - Returns: The verification result
    public func verifyEvent(_ event: NDKEvent, from relay: NDKRelay, stats: inout NDKRelaySignatureStats) async -> NDKSignatureVerificationResult {
        guard let eventId = event.id, let signature = event.sig else {
            return .invalid
        }
        
        // Check if relay is blacklisted
        if blacklistedRelays.contains(relay.url) {
            return .invalid
        }
        
        // Check cache first
        if await cache.isVerified(eventId: eventId, signature: signature) {
            stats.addValidatedEvent()
            return .cached
        }
        
        // Determine if we should verify based on sampling
        let shouldVerify = shouldVerifyEvent(relay: relay, stats: stats)
        
        if !shouldVerify {
            // Skip verification due to sampling
            stats.addNonValidatedEvent()
            updateValidationRatio(relay: relay, stats: &stats)
            return .skipped
        }
        
        // Perform actual signature verification
        let isValid = verifySignature(event: event)
        
        if isValid {
            // Cache the verified signature
            await cache.addVerifiedSignature(eventId: eventId, signature: signature)
            stats.addValidatedEvent()
            updateValidationRatio(relay: relay, stats: &stats)
            totalVerifications += 1
            return .valid
        } else {
            // Invalid signature detected - this relay is evil!
            failedVerifications += 1
            await handleInvalidSignature(event: event, relay: relay)
            return .invalid
        }
    }
    
    /// Check if a relay is blacklisted
    public func isBlacklisted(relay: NDKRelay) -> Bool {
        return blacklistedRelays.contains(relay.url)
    }
    
    /// Get blacklisted relay URLs
    public func getBlacklistedRelays() -> Set<String> {
        return blacklistedRelays
    }
    
    /// Clear the signature cache
    public func clearCache() async {
        await cache.clear()
    }
    
    /// Get verification statistics
    public func getStats() -> (totalVerifications: Int, failedVerifications: Int, blacklistedRelays: Int) {
        return (totalVerifications, failedVerifications, blacklistedRelays.count)
    }
    
    /// Set the signature verification delegate
    public func setDelegate(_ delegate: NDKSignatureVerificationDelegate?) {
        self.delegate = delegate
    }
    
    // MARK: - Private Methods
    
    /// Determine if we should verify an event based on sampling
    private func shouldVerifyEvent(relay: NDKRelay, stats: NDKRelaySignatureStats) -> Bool {
        let ratio = stats.currentValidationRatio
        
        // Always verify if ratio is 1.0
        if ratio >= 1.0 {
            return true
        }
        
        // Otherwise, randomly decide based on ratio
        return Double.random(in: 0..<1) < ratio
    }
    
    /// Update the validation ratio for a relay
    private func updateValidationRatio(relay: NDKRelay, stats: inout NDKRelaySignatureStats) {
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
    private func verifySignature(event: NDKEvent) -> Bool {
        guard let eventId = event.id,
              let signature = event.sig else {
            return false
        }
        
        do {
            // Generate the expected event ID
            let calculatedId = try event.generateID()
            
            // Verify the ID matches
            guard eventId == calculatedId else {
                return false
            }
            
            // Verify the signature
            let messageData = Data(hexString: eventId) ?? Data()
            return try Crypto.verify(signature: signature, message: messageData, publicKey: event.pubkey)
        } catch {
            return false
        }
    }
    
    /// Handle an invalid signature detection
    private func handleInvalidSignature(event: NDKEvent, relay: NDKRelay) async {
        // A single invalid signature means the relay is evil
        print("⚠️ EVIL RELAY DETECTED: \(relay.url) provided event \(event.id ?? "unknown") with invalid signature")
        
        // Notify delegate on main thread
        let delegateCopy = delegate
        await MainActor.run {
            delegateCopy?.signatureVerificationFailed(for: event, from: relay)
        }
        
        // Blacklist the relay if configured
        if config.autoBlacklistInvalidRelays {
            blacklistedRelays.insert(relay.url)
            
            // Notify delegate about blacklisting
            let delegateCopy = delegate
            await MainActor.run {
                delegateCopy?.relayBlacklisted(relay)
            }
            
            // Disconnect from the relay
            Task {
                await relay.disconnect()
            }
        }
    }
}