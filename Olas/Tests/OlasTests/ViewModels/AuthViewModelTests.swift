import XCTest
@testable import Olas
@testable import NDKSwift

final class AuthViewModelTests: XCTestCase {

    func testInitialStateIsLoggedOut() async {
        let viewModel = await AuthViewModel()

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoggedIn)
            XCTAssertNil(viewModel.currentUser)
            XCTAssertNil(viewModel.signer)
        }
    }

    func testCreateAccountGeneratesKeys() async throws {
        let viewModel = await AuthViewModel()

        try await viewModel.createAccount()

        await MainActor.run {
            XCTAssertTrue(viewModel.isLoggedIn)
            XCTAssertNotNil(viewModel.currentUser)
            XCTAssertNotNil(viewModel.signer)
        }
    }

    func testLoginWithValidNsec() async throws {
        let viewModel = await AuthViewModel()

        // Generate a test signer to get a valid nsec
        let testSigner = try NDKPrivateKeySigner.generate()
        let nsec = try testSigner.nsec
        let expectedPubkey = try await testSigner.pubkey

        try await viewModel.loginWithNsec(nsec)

        await MainActor.run {
            XCTAssertTrue(viewModel.isLoggedIn)
            XCTAssertEqual(viewModel.currentUser?.pubkey, expectedPubkey)
        }
    }

    func testLoginWithInvalidNsecThrows() async {
        let viewModel = await AuthViewModel()

        do {
            try await viewModel.loginWithNsec("invalid_nsec")
            XCTFail("Should have thrown an error")
        } catch {
            // Expected - invalid nsec should throw
        }
    }

    func testLoginWithWrongPrefixThrows() async {
        let viewModel = await AuthViewModel()

        do {
            try await viewModel.loginWithNsec("npub1abc123")  // Wrong prefix
            XCTFail("Should have thrown AuthError.invalidNsec")
        } catch let error as AuthError {
            XCTAssertEqual(error, .invalidNsec)
        } catch {
            XCTFail("Expected AuthError.invalidNsec, got \(error)")
        }
    }

    func testLogoutClearsState() async throws {
        let viewModel = await AuthViewModel()
        let testSigner = try NDKPrivateKeySigner.generate()
        let nsec = try testSigner.nsec

        try await viewModel.loginWithNsec(nsec)
        await viewModel.logout()

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoggedIn)
            XCTAssertNil(viewModel.currentUser)
            XCTAssertNil(viewModel.signer)
        }
    }
}
