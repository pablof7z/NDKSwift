import XCTest
@testable import NDKSwift

/// Base test case class for all NDKSwift tests
/// Provides common setup/teardown and utility methods
open class NDKTestCase: XCTestCase {
    
    // MARK: - Properties
    
    /// Temporary directory for test files
    var tempDirectory: URL!
    
    /// Tracks created resources for cleanup
    private var createdNDKInstances: [NDK] = []
    private var createdFiles: [URL] = []
    
    // MARK: - Setup & Teardown
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Configure logging for tests
        NDKLogger.logLevel = .warning // Reduce noise in tests
        NDKLogger.logNetworkTraffic = false
        
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NDKSwiftTests")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }
    
    open override func tearDown() async throws {
        // Disconnect all NDK instances
        for ndk in createdNDKInstances {
            await ndk.disconnect()
        }
        createdNDKInstances.removeAll()
        
        // Clean up temp files
        for fileURL in createdFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
        createdFiles.removeAll()
        
        // Remove temp directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Factory Methods
    
    /// Creates a test NDK instance that will be automatically cleaned up
    func createTestNDK(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cache: NDKCache? = nil,
        debugMode: Bool = false,
        outboxEnabled: Bool = false
    ) -> NDK {
        let ndk = NDKTestFactory.createNDK(
            relayUrls: relayUrls,
            signer: signer,
            cache: cache,
            debugMode: debugMode,
            outboxEnabled: outboxEnabled
        )
        createdNDKInstances.append(ndk)
        return ndk
    }
    
    /// Creates a connected test NDK instance
    func createConnectedTestNDK(
        useTestRelays: Bool = false,
        signer: NDKSigner? = nil
    ) async throws -> NDK {
        let ndk = try await NDKTestFactory.createConnectedNDK(
            useTestRelays: useTestRelays,
            signer: signer
        )
        createdNDKInstances.append(ndk)
        return ndk
    }
    
    /// Creates a test cache backed by a temporary database
    func createTestCache(debugMode: Bool = false) async throws -> NDKSQLiteCache {
        let dbPath = tempDirectory
            .appendingPathComponent("\(UUID().uuidString).db")
            .path
        
        createdFiles.append(URL(fileURLWithPath: dbPath))
        return try await NDKSQLiteCache(path: dbPath, debugMode: debugMode)
    }
    
    /// Creates an in-memory test cache
    func createMemoryCache() -> MemoryCache {
        return MemoryCache()
    }
    
    // MARK: - Test Utilities
    
    /// Waits for a condition with timeout
    func waitForCondition(
        timeout: TimeInterval = 5.0,
        pollingInterval: TimeInterval = 0.1,
        condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }
        
        XCTFail("Condition not met within \(timeout) seconds")
    }
    
    /// Performs an async test with timeout protection
    func performAsyncTest(
        timeout: TimeInterval = 30.0,
        test: @escaping () async throws -> Void
    ) async throws {
        let testTask = Task {
            try await test()
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            testTask.cancel()
            throw XCTSkip("Test timed out after \(timeout) seconds")
        }
        
        do {
            try await testTask.value
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }
    
    /// Measures async operation performance
    func measureAsync(
        metrics: [XCTMetric] = [XCTClockMetric()],
        options: XCTMeasureOptions = XCTMeasureOptions(),
        block: @escaping () async throws -> Void
    ) {
        self.measure(metrics: metrics, options: options) {
            let expectation = self.expectation(description: "async measure")
            
            Task {
                do {
                    try await block()
                } catch {
                    XCTFail("Async measure block threw error: \(error)")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 60.0)
        }
    }
    
    /// Creates a temporary file path
    func createTempFilePath(extension fileExtension: String = "tmp") -> URL {
        let filePath = tempDirectory
            .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        createdFiles.append(filePath)
        return filePath
    }
}

// MARK: - Integration Test Base

/// Base class for integration tests that need real relay connections
open class NDKIntegrationTestCase: NDKTestCase {
    
    /// Test relay URLs for integration tests
    var testRelayUrls: [RelayURL] {
        return RelayConstants.testRelays
    }
    
    /// Timeout for relay operations
    var relayTimeout: TimeInterval {
        return 30.0
    }
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Enable more logging for integration tests
        NDKLogger.logLevel = .info
    }
    
    /// Creates and connects to test relays
    func createConnectedNDK(signer: NDKSigner? = nil) async throws -> NDK {
        let ndk = createTestNDK(
            relayUrls: testRelayUrls,
            signer: signer
        )
        
        await ndk.connect()
        
        // Wait for at least one relay connection
        let connected = await ndk.waitForRelayConnections(
            minimumRelays: 1,
            timeout: relayTimeout
        )
        
        if connected == 0 {
            XCTFail("Failed to connect to any test relays")
        }
        
        return ndk
    }
    
    /// Waits for event to be published and confirmed
    func publishAndWaitForConfirmation(
        event: NDKEvent,
        ndk: NDK,
        timeout: TimeInterval = 10.0
    ) async throws {
        let publishedRelays = try await ndk.publish(event)
        
        XCTAssertFalse(
            publishedRelays.isEmpty,
            "Event was not published to any relays"
        )
        
        // Wait for event to be retrievable
        try await waitForCondition(timeout: timeout) {
            let filter = NDKFilter(ids: [event.id])
            let events = try? await ndk.cache.queryEvents(filter)
            return !(events ?? []).isEmpty
        }
    }
}

// MARK: - Performance Test Base

/// Base class for performance tests
open class NDKPerformanceTestCase: NDKTestCase {
    
    /// Default performance metrics
    var defaultMetrics: [XCTMetric] {
        return [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric()
        ]
    }
    
    /// Default measure options
    var defaultMeasureOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Disable logging for performance tests
        NDKLogger.logLevel = .off
        NDKLogger.logNetworkTraffic = false
    }
    
    /// Measures performance of an async operation
    func measureAsyncPerformance(
        metrics: [XCTMetric]? = nil,
        options: XCTMeasureOptions? = nil,
        block: @escaping () async throws -> Void
    ) {
        measureAsync(
            metrics: metrics ?? defaultMetrics,
            options: options ?? defaultMeasureOptions,
            block: block
        )
    }
    
    /// Creates large test data set
    func createLargeEventSet(count: Int, kind: Kind = 1) -> [NDKEvent] {
        return (0..<count).map { index in
            EventTestFactory.createEvent(
                kind: kind,
                content: "Performance test event #\(index)",
                pubkey: TestFixtures.Keys.alice.publicKey,
                createdAt: Timestamp.now + Timestamp(index)
            )
        }
    }
}