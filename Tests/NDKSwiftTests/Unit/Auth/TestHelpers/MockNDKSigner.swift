import Foundation
@testable import NDKSwiftCore

/// Mock signer for testing authentication flows
final class MockNDKSigner: NDKSigner {
    static let signerType = "mock-signer"

    private let _pubkey: PublicKey
    private let privateKey: PrivateKey?
    var requiresBiometric: Bool
    var isHardwareBacked: Bool
    var signEventCalled = false
    var lastSignedEvent: NDKEvent?

    var pubkey: PublicKey {
        get async throws {
            return _pubkey
        }
    }

    init(
        publicKey: PublicKey? = nil,
        privateKey: PrivateKey? = nil,
        requiresBiometric: Bool = false,
        isHardwareBacked: Bool = false
    ) {
        _pubkey = publicKey ?? "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f"
        self.privateKey = privateKey ?? "8f40e50a84a7462e2b8d24c28898ef0ce0d0113a0a2ce9648e6006b79c7e5185"
        self.requiresBiometric = requiresBiometric
        self.isHardwareBacked = isHardwareBacked
    }

    func sign(_ event: NDKEvent) async throws -> Signature {
        signEventCalled = true
        lastSignedEvent = event

        // Use real signature if we have a private key
        if let privateKey = privateKey {
            let idData = try HexValidator.validate32ByteHex(event.id)
            let signature = try Crypto.sign(message: idData, privateKey: privateKey)
            return signature
        }

        // Fallback to dummy signature (which will fail validation)
        return "9a59a5f40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b"
    }

    func encrypt(recipient _: NDKUser, value: String, scheme _: NDKEncryptionScheme) async throws -> String {
        // Simple mock encryption
        return "encrypted:\(value)"
    }

    func decrypt(sender _: NDKUser, value: String, scheme _: NDKEncryptionScheme) async throws -> String {
        // Simple mock decryption
        if value.starts(with: "encrypted:") {
            return String(value.dropFirst("encrypted:".count))
        }
        return value
    }

    func serialize() async throws -> Data {
        let data: [String: Any] = [
            "type": MockNDKSigner.signerType,
            "publicKey": _pubkey,
            "privateKey": privateKey ?? "",
            "requiresBiometric": requiresBiometric,
            "isHardwareBacked": isHardwareBacked,
        ]
        return try JSONSerialization.data(withJSONObject: data)
    }

    static func deserialize(_ data: Data, ndk _: NDK?) throws -> Self {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publicKey = dict["publicKey"] as? String
        else {
            throw NDKError.invalidContent("Missing public key in serialized data")
        }

        let privateKey = dict["privateKey"] as? String
        let requiresBiometric = dict["requiresBiometric"] as? Bool ?? false
        let isHardwareBacked = dict["isHardwareBacked"] as? Bool ?? false

        return MockNDKSigner(
            publicKey: publicKey,
            privateKey: privateKey?.isEmpty == false ? privateKey : nil,
            requiresBiometric: requiresBiometric,
            isHardwareBacked: isHardwareBacked
        ) as! Self
    }
}

/// Mock signer that requires biometric authentication
final class MockBiometricSigner: NDKSigner {
    static let signerType = "mock-biometric-signer"

    private let _pubkey: PublicKey
    var requiresBiometric: Bool
    var isHardwareBacked: Bool

    var pubkey: PublicKey {
        get async throws {
            return _pubkey
        }
    }

    init(publicKey: PublicKey? = nil) {
        _pubkey = publicKey ?? "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f"
        requiresBiometric = true
        isHardwareBacked = true
    }

    func sign(_: NDKEvent) async throws -> Signature {
        return "9a59a5f40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b"
    }

    func encrypt(recipient _: NDKUser, value: String, scheme _: NDKEncryptionScheme) async throws -> String {
        return "encrypted:\(value)"
    }

    func decrypt(sender _: NDKUser, value: String, scheme _: NDKEncryptionScheme) async throws -> String {
        if value.starts(with: "encrypted:") {
            return String(value.dropFirst("encrypted:".count))
        }
        return value
    }

    func serialize() async throws -> Data {
        let data: [String: Any] = [
            "type": MockBiometricSigner.signerType,
            "publicKey": _pubkey,
            "requiresBiometric": requiresBiometric,
            "isHardwareBacked": isHardwareBacked,
        ]
        return try JSONSerialization.data(withJSONObject: data)
    }

    static func deserialize(_ data: Data, ndk _: NDK?) throws -> Self {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publicKey = dict["publicKey"] as? String
        else {
            throw NDKError.invalidContent("Missing public key in serialized data")
        }

        return MockBiometricSigner(publicKey: publicKey) as! Self
    }
}
