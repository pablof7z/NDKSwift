import Foundation

extension NDKError {
    static func failedTo(_ operation: String, message: String? = nil, underlying: Error? = nil) -> NDKError {
        let fullMessage = message.map { "Failed to \(operation): \($0)" } ?? "Failed to \(operation)"
        return .unknown(fullMessage, underlying: underlying)
    }
    
    static func invalidDataFormat(_ dataType: String, details: String? = nil) -> NDKError {
        let message = details.map { "Invalid \(dataType): \($0)" } ?? "Invalid \(dataType)"
        return .invalidInput(message: message)
    }
    
    static func missingRequired(_ field: String, in context: String? = nil) -> NDKError {
        let message = context.map { "Missing required \(field) in \($0)" } ?? "Missing required \(field)"
        return .invalidInput(message: message)
    }
    
    static func networkError(for relay: String, operation: String, error: Error) -> NDKError {
        return .connectionFailed(relay: relay, message: "Failed to \(operation)", underlying: error)
    }
    
    static func parseError(for type: String, details: String? = nil) -> NDKError {
        let message = details.map { "Failed to parse \(type): \($0)" } ?? "Failed to parse \(type)"
        return .invalidInput(message: message)
    }
    
    static func cryptoOperation(_ operation: String, nip: String? = nil, error: Error) -> NDKError {
        let message = nip.map { "\(operation) failed (\($0))" } ?? "\(operation) failed"
        
        switch operation.lowercased() {
        case "encryption", "encrypt":
            return .encryptionFailed(message, underlying: error)
        case "decryption", "decrypt":
            return .decryptionFailed(message, underlying: error)
        case "signing", "sign":
            return .signingFailed(message, underlying: error)
        case "verification", "verify":
            return .verificationFailed(message, underlying: error)
        case "key derivation":
            return .keyDerivationFailed(message, underlying: error)
        default:
            return .unknown(message, underlying: error)
        }
    }
}