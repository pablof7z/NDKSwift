@testable import NDKSwiftCore
import XCTest

@MainActor
final class NostrConnectURIBuilderTests: XCTestCase {
    private func makeNDK() async throws -> NDK {
        return try await NDKTestFactory.createNDK()
    }

    // MARK: - extraQueryItems

    func testExtraQueryItemsAppearInGeneratedURI() async throws {
        let ndk = try await makeNDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "MyApp",
            extraQueryItems: [
                URLQueryItem(name: "callback", value: "myapp://nip46"),
                URLQueryItem(name: "vendor_flag", value: "1"),
            ]
        )

        let signer = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.example.com"],
            localSigner: localSigner,
            options: options
        )

        let maybeURI = await signer.nostrConnectUri
        let uri = try XCTUnwrap(maybeURI)
        let components = try XCTUnwrap(URLComponents(string: uri))
        let items = components.queryItems ?? []

        XCTAssertTrue(items.contains(URLQueryItem(name: "callback", value: "myapp://nip46")),
                      "Expected callback query item in URI: \(uri)")
        XCTAssertTrue(items.contains(URLQueryItem(name: "vendor_flag", value: "1")),
                      "Expected vendor_flag query item in URI: \(uri)")
    }

    func testNilExtraQueryItemsBackwardCompatible() async throws {
        let ndk = try await makeNDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        let options = NDKBunkerSigner.NostrConnectOptions(name: "MyApp", url: "https://myapp.com")

        let signer = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.example.com"],
            localSigner: localSigner,
            options: options
        )

        let maybeURI = await signer.nostrConnectUri
        let uri = try XCTUnwrap(maybeURI)
        XCTAssertTrue(uri.hasPrefix("nostrconnect://"))
        XCTAssertTrue(uri.contains("name=MyApp"))
        XCTAssertTrue(uri.contains("url=https://myapp.com"))
    }

    // MARK: - URI structure

    func testURISchemeAndHostAreCorrect() async throws {
        let ndk = try await makeNDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        let expectedPubkey = try await localSigner.pubkey

        let signer = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.example.com"],
            localSigner: localSigner
        )

        let maybeURI = await signer.nostrConnectUri
        let uri = try XCTUnwrap(maybeURI)
        let components = try XCTUnwrap(URLComponents(string: uri))
        XCTAssertEqual(components.scheme, "nostrconnect")
        XCTAssertEqual(components.host, expectedPubkey)
    }

    func testMultipleRelaysProduceMultipleRelayQueryItems() async throws {
        let ndk = try await makeNDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        let relays = ["wss://relay1.example.com", "wss://relay2.example.com"]

        let signer = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: relays,
            localSigner: localSigner
        )

        let maybeURI = await signer.nostrConnectUri
        let uri = try XCTUnwrap(maybeURI)
        let components = try XCTUnwrap(URLComponents(string: uri))
        let relayValues = (components.queryItems ?? [])
            .filter { $0.name == "relay" }
            .compactMap(\.value)
        XCTAssertEqual(Set(relayValues), Set(relays))
    }

    func testValuesWithSpacesArePercentEncoded() async throws {
        let ndk = try await makeNDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        let options = NDKBunkerSigner.NostrConnectOptions(name: "Hello World")

        let signer = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.example.com"],
            localSigner: localSigner,
            options: options
        )

        let maybeURI = await signer.nostrConnectUri
        let uri = try XCTUnwrap(maybeURI)
        XCTAssertTrue(uri.contains("name=Hello%20World"), "Expected percent-encoded space in: \(uri)")

        // Re-parsed via URLComponents the value should round-trip as the original string.
        let components = try XCTUnwrap(URLComponents(string: uri))
        let nameValue = (components.queryItems ?? []).first(where: { $0.name == "name" })?.value
        XCTAssertEqual(nameValue, "Hello World")
    }
}
