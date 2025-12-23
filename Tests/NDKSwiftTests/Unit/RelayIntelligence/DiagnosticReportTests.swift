import XCTest
@testable import NDKSwiftCore

final class DiagnosticReportTests: XCTestCase {
    // MARK: - Diagnostic Report Tests

    func test_diagnosticReport_includesHintIndexStats() async {
        let ndk = NDK()

        // Add some hints
        await ndk.hintIndex.recordHint(pubkey: "p1", relay: "wss://r1.example.com", source: .eventObserved)
        await ndk.hintIndex.recordHint(pubkey: "p2", relay: "wss://r2.example.com", source: .nip19)

        let report = await ndk.relayIntelligenceDiagnostics()

        XCTAssertEqual(report.hintIndex.pubkeyCount, 2)
        XCTAssertEqual(report.hintIndex.totalEntries, 2)
    }

    func test_diagnosticReport_includesPoolStats() async {
        let ndk = NDK()

        // Add some relays
        _ = await ndk.pool.addRelay("wss://relay1.example.com", origin: .explicit)
        _ = await ndk.pool.addRelay("wss://relay2.example.com", origin: .outbox(authorPubkey: "test"))

        let report = await ndk.relayIntelligenceDiagnostics()

        XCTAssertEqual(report.pool.totalRelays, 2)
        XCTAssertEqual(report.pool.persistentRelays, 1)
    }

    func test_diagnosticReport_includesMostKnownRelays() async {
        let ndk = NDK()

        // Add multiple hints for same relay
        await ndk.hintIndex.recordHint(pubkey: "p1", relay: "wss://popular.example.com", source: .eventObserved)
        await ndk.hintIndex.recordHint(pubkey: "p2", relay: "wss://popular.example.com", source: .eventObserved)
        await ndk.hintIndex.recordHint(pubkey: "p3", relay: "wss://less-popular.example.com", source: .eventObserved)

        let report = await ndk.relayIntelligenceDiagnostics()

        XCTAssertFalse(report.mostKnownRelays.isEmpty)
        XCTAssertEqual(report.mostKnownRelays.first?.relay, "wss://popular.example.com/")
    }

    func test_diagnosticReport_includesSourceBreakdown() async {
        let ndk = NDK()

        await ndk.hintIndex.recordHint(pubkey: "p1", relay: "wss://r1.example.com", source: .eventObserved)
        await ndk.hintIndex.recordHint(pubkey: "p2", relay: "wss://r2.example.com", source: .nip19)
        await ndk.hintIndex.recordHint(pubkey: "p3", relay: "wss://r3.example.com", source: .nip19)

        let report = await ndk.relayIntelligenceDiagnostics()

        XCTAssertEqual(report.hintSourceBreakdown[.eventObserved], 1)
        XCTAssertEqual(report.hintSourceBreakdown[.nip19], 2)
    }
}
