import Foundation
import NDKSwiftCore

extension NDKPrivateKeySigner {
    static func from(userInput: String) throws -> NDKPrivateKeySigner {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if input is nsec (bech32) format
        if trimmedInput.lowercased().hasPrefix("nsec") {
            return try NDKPrivateKeySigner(nsec: trimmedInput)
        } else {
            // Assume hex format
            return try NDKPrivateKeySigner(privateKey: trimmedInput)
        }
    }
}
