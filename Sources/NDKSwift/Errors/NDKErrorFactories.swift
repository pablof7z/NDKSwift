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
}