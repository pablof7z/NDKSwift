/// Factory methods for creating NDKError instances with consistent messaging
extension NDKError {
    static func failedTo(_ operation: String, message: String? = nil, underlying: Error? = nil) -> NDKError {
        let fullMessage = message.map { "\(ErrorMessageConstants.failedTo(operation)): \($0)" } ?? ErrorMessageConstants.failedTo(operation)
        return .unknown(fullMessage, underlying: underlying)
    }

    static func invalidDataFormat(_ dataType: String, details: String? = nil) -> NDKError {
        let message = details.map { "\(ErrorMessageConstants.invalid(dataType)): \($0)" } ?? ErrorMessageConstants.invalid(dataType)
        return .invalidInput(message: message)
    }

    static func missingRequired(_ field: String, in context: String? = nil) -> NDKError {
        let message = context.map { "\(ErrorMessageConstants.missing(field)) in \($0)" } ?? ErrorMessageConstants.missing(field)
        return .invalidInput(message: message)
    }

    static func networkError(for relay: String, operation: String, error: Error) -> NDKError {
        return .connectionFailed(relay: relay, message: ErrorMessageConstants.failedTo(operation), underlying: error)
    }

    static func parseError(for type: String, details: String? = nil) -> NDKError {
        let message = details.map { "\(ErrorMessageConstants.failedToParse) \(type): \($0)" } ?? "\(ErrorMessageConstants.failedToParse) \(type)"
        return .invalidInput(message: message)
    }

    static func cryptoOperation(_ operation: String, nip: String? = nil, error: Error) -> NDKError {
        let message = nip.map { "\(operation) failed (\($0))" } ?? "\(operation) failed"

        let operationMap: [String: (String, Error?) -> NDKError] = [
            "encryption": NDKError.encryptionFailed,
            "encrypt": NDKError.encryptionFailed,
            "decryption": NDKError.decryptionFailed,
            "decrypt": NDKError.decryptionFailed,
            "signing": NDKError.signingFailed,
            "sign": NDKError.signingFailed,
            "verification": NDKError.verificationFailed,
            "verify": NDKError.verificationFailed,
            "key derivation": NDKError.keyDerivationFailed
        ]

        let lowercased = operation.lowercased()
        return operationMap[lowercased]?(message, error) ?? .unknown(message, underlying: error)
    }

    static func validationError(_ message: String) -> NDKError {
        return .invalidInput(message: message)
    }

    static func configurationError(_ message: String) -> NDKError {
        return .notConfigured(message)
    }
    
    // MARK: - Wallet-specific error factories
    
    static func walletInsufficientBalance(amount: Int64, available: Int64? = nil) -> NDKError {
        if let available = available {
            return .walletError(message: "Insufficient balance: requested \(amount) sats, available: \(available) sats")
        } else {
            return .insufficientBalance(amount: amount)
        }
    }
    
    static func walletMintError(_ mintURL: String, operation: String, details: String? = nil) -> NDKError {
        let message = details.map { "Mint \(mintURL) \(operation) failed: \($0)" }
            ?? "Mint \(mintURL) \(operation) failed"
        return .walletError(message: message)
    }
    
    static func walletPaymentFailed(reason: String, invoice: String? = nil) -> NDKError {
        let message = invoice.map { "Payment failed for invoice \($0): \(reason)" }
            ?? "Payment failed: \(reason)"
        return .paymentFailed(reason: message)
    }
    
    static func walletInvalidProof(details: String? = nil) -> NDKError {
        let message = details.map { "Invalid proof: \($0)" } ?? "Invalid proof"
        return .invalidProof(message)
    }
    
    static func walletNoMintAvailable(reason: String? = nil) -> NDKError {
        let message = reason ?? "No mint available"
        return .noMintAvailable(message)
    }
}