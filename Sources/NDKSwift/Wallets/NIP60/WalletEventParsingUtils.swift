import Foundation

/// Utility for common wallet event parsing operations
enum WalletEventParsingUtils {
    /// Decrypts event content and parses it into the specified type
    /// - Parameters:
    ///   - event: The event containing encrypted content
    ///   - signer: The signer to use for decryption
    ///   - scheme: The encryption scheme to use (defaults to NIP-44)
    /// - Returns: The decrypted and parsed object
    /// - Throws: NDKError if decryption or parsing fails
    static func decryptAndParse<T: Decodable>(
        event: NDKEvent,
        signer: NDKSigner,
        scheme: NDKEncryptionScheme = .nip44
    ) async throws -> T {
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: scheme
        )
        
        guard let data = decryptedContent.data(using: .utf8) else {
            throw NDKError.invalidContent("Decrypted content not valid UTF-8 for event \(event.id)")
        }
        
        return try JSONCoding.decode(T.self, from: data)
    }
    
    /// Decrypts event content and attempts to parse it, returning nil on failure
    /// - Parameters:
    ///   - event: The event containing encrypted content
    ///   - signer: The signer to use for decryption
    ///   - scheme: The encryption scheme to use (defaults to NIP-44)
    /// - Returns: The decrypted and parsed object, or nil if parsing fails
    static func safeDecryptAndParse<T: Decodable>(
        event: NDKEvent,
        signer: NDKSigner,
        scheme: NDKEncryptionScheme = .nip44
    ) async -> T? {
        do {
            return try await decryptAndParse(event: event, signer: signer, scheme: scheme)
        } catch {
            NDKLogger.log(.error, category: .wallet, "Failed to decrypt/parse event \(event.id): \(error)")
            return nil
        }
    }
    
    /// Validates that an event has the expected kind and required tags
    /// - Parameters:
    ///   - event: The event to validate
    ///   - expectedKind: The expected event kind
    ///   - requiredTags: Tag names that must be present
    /// - Throws: NDKError if validation fails
    static func validateEvent(
        _ event: NDKEvent,
        expectedKind: Kind,
        requiredTags: [String] = []
    ) throws {
        guard event.kind == expectedKind else {
            throw NDKError.invalidInput(message: "Expected kind \(expectedKind) but got \(event.kind)")
        }
        
        for tagName in requiredTags {
            if event.tags(withName: tagName).isEmpty {
                throw NDKError.missingRequired(tagName, in: "event \(event.id)")
            }
        }
    }
}