import Foundation

// MARK: - ZapManager Integration

extension NDKZapManager {
    /// Configure the ZapManager to use a SparkWallet as the primary Lightning payment provider
    /// - Parameter sparkWallet: The SparkWallet instance to use for payments
    public func configureWithSpark(sparkWallet: SparkWallet) {
        register(provider: sparkWallet)
    }
}

// MARK: - NDK Extension

extension NDK {
    /// Create and connect a SparkWallet
    /// - Parameters:
    ///   - apiKey: Breez API key
    ///   - mnemonic: BIP39 mnemonic phrase
    ///   - registerWithZapManager: Whether to automatically register with ZapManager (default: true)
    /// - Returns: Connected SparkWallet instance
    public func createSparkWallet(
        apiKey: String,
        mnemonic: String,
        registerWithZapManager: Bool = true
    ) async throws -> SparkWallet {
        let wallet = SparkWallet(apiKey: apiKey)
        try await wallet.connect(mnemonic: mnemonic)

        if registerWithZapManager {
            await zapManager.configureWithSpark(sparkWallet: wallet)
        }

        return wallet
    }

    /// Create a new SparkWallet with fresh mnemonic
    /// - Parameters:
    ///   - apiKey: Breez API key
    ///   - registerWithZapManager: Whether to automatically register with ZapManager (default: true)
    /// - Returns: Tuple of (SparkWallet, mnemonic)
    public func createNewSparkWallet(
        apiKey: String,
        registerWithZapManager: Bool = true
    ) async throws -> (wallet: SparkWallet, mnemonic: String) {
        let wallet = SparkWallet(apiKey: apiKey)
        let mnemonic = try await wallet.createWallet()

        if registerWithZapManager {
            await zapManager.configureWithSpark(sparkWallet: wallet)
        }

        return (wallet, mnemonic)
    }
}

// MARK: - Combined Wallet Setup

extension NDKZapManager {
    /// Configure defaults with optional Spark wallet support
    /// - Parameters:
    ///   - sparkWallet: Optional SparkWallet for Lightning payments
    ///   - cashuWallet: Optional NIP60 wallet for Cashu/Nutzap payments
    ///   - nwcWallet: Optional NWC wallet for Lightning payments
    public func configureDefaults(
        sparkWallet: SparkWallet? = nil,
        cashuWallet: NIP60Wallet? = nil,
        nwcWallet: NDKNWCWallet? = nil
    ) {
        // Clear existing providers
        // Note: The actual implementation would need access to clear providers

        // Priority order: Cashu (most private) > Spark (self-custodial) > NWC > QR fallback

        if let cashuWallet = cashuWallet {
            register(provider: cashuWallet)
        }

        if let sparkWallet = sparkWallet {
            register(provider: sparkWallet)
        }

        if let nwcWallet = nwcWallet {
            register(provider: nwcWallet)
        }

        // Always add QR code as fallback
        register(provider: QRCodePaymentProvider())
    }
}
