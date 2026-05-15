import Foundation
@testable import NDKSwiftCore
import XCTest

final class NDKEncryptedDirectMessageTests: XCTestCase {
    func testEncryptedDirectMessageDefaultsToNIP04Kind4Payload() async throws {
        let sender = try NDKPrivateKeySigner.generate()
        let recipient = try NDKPrivateKeySigner.generate()
        let recipientPubkey = try await recipient.pubkey
        let ndk = try await NDKTestFactory.createNDK(signer: sender)

        let event = try await NDKEvent.encryptedDirectMessage(
            content: "legacy dm",
            recipientPubkey: recipientPubkey,
            signer: sender,
            ndk: ndk
        )

        XCTAssertEqual(event.kind, EventKind.encryptedDirectMessage)
        XCTAssertTrue(event.content.contains("?iv="))
        let decrypted = try await event.decryptedContent(signer: recipient)
        XCTAssertEqual(decrypted, "legacy dm")
    }

    func testDecryptedContentRejectsTamperedEventBeforeDecrypting() async throws {
        let sender = try NDKPrivateKeySigner.generate()
        let recipient = try NDKPrivateKeySigner.generate()
        let recipientPubkey = try await recipient.pubkey
        let ndk = try await NDKTestFactory.createNDK(signer: sender)

        let event = try await NDKEvent.encryptedDirectMessage(
            content: "secret payload",
            recipientPubkey: recipientPubkey,
            signer: sender,
            ndk: ndk
        )

        let tampered = NDKEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: "\(event.content)tampered",
            sig: event.sig
        )
        let decryptSpy = RecordingDecryptSigner(pubkey: recipientPubkey)

        do {
            _ = try await tampered.decryptedContent(signer: decryptSpy)
            XCTFail("Expected tampered encrypted event to be rejected")
        } catch {
            let decryptCallCount = await decryptSpy.decryptCallCount
            XCTAssertEqual(decryptCallCount, 0)
        }
    }
}

private actor RecordingDecryptSigner: NDKSigner {
    static let signerType = "recording-decrypt-signer"

    private var _decryptCallCount = 0
    private let signerPubkey: PublicKey

    var decryptCallCount: Int {
        return _decryptCallCount
    }

    var pubkey: PublicKey {
        get async throws { signerPubkey }
    }

    init(pubkey: PublicKey) {
        signerPubkey = pubkey
    }

    func sign(_: NDKEvent) async throws -> Signature {
        throw NDKError.notImplemented("RecordingDecryptSigner.sign")
    }

    func encrypt(recipientPubkey _: PublicKey, value _: String, scheme _: NDKEncryptionScheme) async throws -> String {
        throw NDKError.notImplemented("RecordingDecryptSigner.encrypt")
    }

    func decrypt(senderPubkey _: PublicKey, value _: String, scheme _: NDKEncryptionScheme) async throws -> String {
        _decryptCallCount += 1
        throw NDKError.invalidMessage("decrypt should not be called")
    }

    func serialize() async throws -> Data {
        Data()
    }

    static func deserialize(_: Data, ndk _: NDK?) async throws -> RecordingDecryptSigner {
        throw NDKError.notImplemented("RecordingDecryptSigner.deserialize")
    }
}
