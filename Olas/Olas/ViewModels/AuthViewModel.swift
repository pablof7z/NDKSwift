import Foundation
import SwiftUI
import NDKSwift

@MainActor
@Observable
final class AuthViewModel {
    public private(set) var isLoggedIn = false
    public private(set) var currentUser: NDKUser?
    public private(set) var isLoading = false
    public var error: Error?

    public private(set) var signer: NDKPrivateKeySigner?

    public init() {
        // Session restoration happens in restoreSession()
    }

    // MARK: - Public Methods

    public func createAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        let newSigner = try NDKPrivateKeySigner.generate()
        let nsec = try newSigner.nsec

        try KeychainService.save(nsec, for: .userNsec)

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
        try KeychainService.save(nsec, for: .userNsec)

        signer = newSigner
        currentUser = try await newSigner.user()
        isLoggedIn = true
    }

    public func logout() async {
        KeychainService.delete(for: .userNsec)
        signer = nil
        currentUser = nil
        isLoggedIn = false
    }

    public func restoreSession() async {
        guard let nsec = KeychainService.load(for: .userNsec) else { return }

        do {
            try await loginWithNsec(nsec)
        } catch {
            KeychainService.delete(for: .userNsec)
        }
    }
}

// MARK: - Errors

enum AuthError: LocalizedError, Equatable {
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
