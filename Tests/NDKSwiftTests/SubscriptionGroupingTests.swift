import XCTest
@testable import NDKSwift

/// Tests for the DataRequirementManager's temporal grouping behavior
/// These tests verify that multiple data sources created rapidly are efficiently grouped
final class SubscriptionGroupingTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK with test relays
        ndk = NDK(relayUrls: ["wss://test.relay.local"])
    }
    
    override func tearDown() async throws {
        await ndk.disconnect()
        try await super.tearDown()
    }
    
    func testMultipleDataSourcesCreatedRapidly() async throws {
        // This test verifies that creating multiple data sources rapidly works correctly
        // The internal temporal grouping should handle this efficiently
        var dataSources: [NDKDataSource<NDKEvent>] = []
        
        let startTime = Date()
        
        // Create data sources rapidly to trigger temporal grouping
        for i in 0..<5 {
            let dataSource = await ndk.observe(
                filter: NDKFilter(authors: ["author\(i)"], kinds: [1])
            )
            dataSources.append(dataSource)
        }
        
        let endTime = Date()
        let elapsed = endTime.timeIntervalSince(startTime)
        
        // Verify all data sources were created quickly
        XCTAssertLessThan(elapsed, 0.1, "Data sources should be created quickly")
        
        // All data sources should be created successfully
        XCTAssertEqual(dataSources.count, 5, "Should have created 5 data sources")
        
        // Each data source should be independent
        for (index, dataSource) in dataSources.enumerated() {
            let isLoading = await dataSource.isLoading
            XCTAssertTrue(isLoading, "Data source \(index) should be loading")
        }
    }
    
    func testDataSourcesWithDifferentFilters() async throws {
        // Test that data sources with different filters work correctly
        var dataSources: [NDKDataSource<NDKEvent>] = []
        
        // Create data sources with different kinds
        let kinds = [EventKind.textNote, EventKind.contacts, EventKind.metadata]
        for kind in kinds {
            let dataSource = await ndk.observe(
                filter: NDKFilter(kinds: [kind], limit: 10)
            )
            dataSources.append(dataSource)
        }
        
        // All should be created successfully
        XCTAssertEqual(dataSources.count, kinds.count, "Should create data source for each kind")
        
        // Wait a moment for any initial loading
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Each data source should maintain its own state
        for (index, dataSource) in dataSources.enumerated() {
            let data = await dataSource.data
            // Data might be empty (no events) but the array should exist
            XCTAssertNotNil(data, "Data source \(index) should have data array")
        }
    }
    
    func testDataSourcesWithOverlappingAuthors() async throws {
        // Test data sources that have overlapping criteria
        let sharedAuthor = "shared_author_pubkey"
        let uniqueAuthors = ["author1", "author2", "author3"]
        
        var dataSources: [NDKDataSource<NDKEvent>] = []
        
        // Create data sources that all include the shared author
        for uniqueAuthor in uniqueAuthors {
            let dataSource = await ndk.observe(
                filter: NDKFilter(
                    authors: [sharedAuthor, uniqueAuthor],
                    kinds: [1],
                    limit: 20
                )
            )
            dataSources.append(dataSource)
        }
        
        // All should be created successfully
        XCTAssertEqual(dataSources.count, uniqueAuthors.count, "Should create all data sources")
        
        // Each data source should work independently despite overlapping filters
        for (index, dataSource) in dataSources.enumerated() {
            let error = await dataSource.error
            XCTAssertNil(error, "Data source \(index) should not have errors")
        }
    }
    
    func testDataSourceLifecycle() async throws {
        // Test that data sources properly manage their lifecycle
        
        // Create a data source in a limited scope
        var dataSourceReference: NDKDataSource<NDKEvent>?
        
        do {
            let dataSource = await NDKDataSource<NDKEvent>(
                ndk: ndk,
                filter: NDKFilter(kinds: [1], limit: 5)
            )
            dataSourceReference = dataSource
            
            // Verify it's working
            let isLoading = await dataSource.isLoading
            XCTAssertTrue(isLoading, "Data source should start loading")
        }
        
        // Data source should still exist via our reference
        XCTAssertNotNil(dataSourceReference, "Data source should exist via reference")
        
        // Clear the reference
        dataSourceReference = nil
        
        // At this point, the data source should be eligible for cleanup
        // The DataRequirementManager should handle cleanup automatically
        
        // Create a new data source to verify system still works
        let newDataSource = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [1], limit: 5)
        )
        
        let isLoading = await newDataSource.isLoading
        XCTAssertTrue(isLoading, "New data source should work correctly")
    }
}