import Foundation
import SwiftUI
import NDKSwift
import Security

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public private(set) var isLoggedIn = false
    @Published public private(set) var currentUser: NDKUser?
    @Published public private(set) var isLoading = false
    @Published public var error: Error?

    public private(set) var signer: NDKPrivateKeySigner?

    private let keychainService = "com.olas.keychain"
    private let keychainAccount = "user_nsec"

    public init() {
        // Session restoration happens in restoreSession()
    }

    // MARK: - Public Methods

    public func createAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        let newSigner = try NDKPrivateKeySigner.generate()
        let nsec = try newSigner.nsec

        try saveToKeychain(nsec: nsec)

        signer = newSigner
        currentUser = try await newSigner.user()
        isLoggedIn = true
    }

    public func loginWithNsec(_ nsec: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard nsec.hasPrefix("nsec1") else {
            throw AuthError.invalidNsec
        }

        let newSigner = try NDKPrivateKeySigner(nsec: nsec)
        try saveToKeychain(nsec: nsec)

        signer = newSigner
        currentUser = try await newSigner.user()
        isLoggedIn = true
    }

    public func logout() async {
        deleteFromKeychain()
        signer = nil
        currentUser = nil
        isLoggedIn = false
    }

    public func restoreSession() async {
        guard let nsec = loadFromKeychain() else { return }

        do {
            try await loginWithNsec(nsec)
        } catch {
            deleteFromKeychain()
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(nsec: String) throws {
        guard let data = nsec.data(using: .utf8) else {
            throw AuthError.keychainError(-1)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError(status)
        }
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let nsec = String(data: data, encoding: .utf8) else {
            return nil
        }

        return nsec
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum AuthError: LocalizedError, Equatable {
    case invalidNsec
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidNsec:
            return "Invalid private key format. Must start with 'nsec1'"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
