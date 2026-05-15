import Foundation

enum NIP77PayloadValidation {
    static let maxPayloadBytes = 1_048_576

    static func validationError(for hex: String, field: String) -> String? {
        let hexByteCount = hex.utf8.count

        guard hexByteCount > 0 else {
            return "\(field) must not be empty"
        }

        guard hexByteCount.isMultiple(of: 2) else {
            return "\(field) must contain an even number of hex characters"
        }

        let payloadBytes = hexByteCount / 2
        guard payloadBytes <= maxPayloadBytes else {
            return "\(field) exceeds \(maxPayloadBytes) byte limit"
        }

        guard hex.utf8.allSatisfy(isStrictHexByte) else {
            return "\(field) must be strict hex without prefixes or non-hex characters"
        }

        return nil
    }

    static func validateHexPayload(_ hex: String, field: String) throws -> Data {
        if let reason = validationError(for: hex, field: field) {
            throw NIP77Error.invalidMessageFormat(reason)
        }

        guard let data = Data(hexString: hex), data.count == hex.utf8.count / 2 else {
            throw NIP77Error.invalidMessageFormat("\(field) could not be decoded")
        }

        return data
    }

    private static func isStrictHexByte(_ byte: UInt8) -> Bool {
        return (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 70)
            || (byte >= 97 && byte <= 102)
    }
}
