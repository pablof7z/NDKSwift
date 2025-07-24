import XCTest
@testable import NDKSwift

final class BlossomE2ETests: XCTestCase {
    
    // Test configuration
    let testRelays = ["wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol"]
    let testBlossomServers = ["https://blossom.primal.net", "https://files.v0l.io"]
    let timeout: TimeInterval = 30.0
    
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.logLevel = .debug
        NDKLogger.enabledCategories = [.general, .network, .event]
    }
    
    // MARK: - Basic Upload/Download Flow
    
    func testBasicBlossomUploadDownloadE2E() async throws {
        NDKLogger.log(.info, category: .general, "🧪 Starting testBasicBlossomUploadDownloadE2E")
        let startTime = Date()
        
        // Create NDK instance
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let pubkey = try await signer.pubkey
        NDKLogger.log(.debug, category: .general, "Created test user: \(pubkey.prefix(8))...")
        
        // Create test data
        let testContent = "Hello from Blossom E2E test - \(UUID().uuidString)"
        let testData = testContent.data(using: .utf8)!
        let fileName = "test-\(UUID().uuidString).txt"
        
        NDKLogger.log(.debug, category: .general, "Test file: \(fileName), size: \(testData.count) bytes")
        
        // Upload to Blossom
        NDKLogger.log(.info, category: .general, "Uploading file to Blossom servers...")
        
        let blobs = try await NDKLogger.logTiming(.debug, category: .general, operation: "Blossom upload") {
            try await ndk.uploadToBlossom(
                data: testData,
                mimeType: "text/plain",
                servers: testBlossomServers
            )
        }
        
        XCTAssertFalse(blobs.isEmpty, "Should have at least one successful upload")
        NDKLogger.log(.info, category: .general, "✅ Uploaded to \(blobs.count) servers")
        
        for blob in blobs {
            NDKLogger.log(.debug, category: .general, "Blob: \(blob.url), SHA256: \(blob.sha256)")
        }
        
        // Get SHA256 from the first blob
        guard let firstBlob = blobs.first else {
            XCTFail("No blobs returned")
            return
        }
        let sha256 = firstBlob.sha256
        
        NDKLogger.log(.debug, category: .general, "Extracted SHA256: \(sha256)")
        
        // Download from Blossom
        NDKLogger.log(.info, category: .general, "Downloading file from Blossom...")
        
        let blossomClient = ndk.blossomClient
        
        let downloadedData = try await NDKLogger.logTiming(.debug, category: .general, operation: "Blossom download") {
            try await blossomClient.download(sha256: sha256, from: testBlossomServers[0])
        }
        
        // Verify content
        let downloadedContent = String(data: downloadedData, encoding: .utf8)
        XCTAssertEqual(downloadedContent, testContent, "Downloaded content should match uploaded content")
        
        NDKLogger.log(.info, category: .general, "✅ Downloaded and verified content matches")
        NDKLogger.log(.info, category: .general, "✅ Basic Blossom E2E test completed in \(Date().timeIntervalSince(startTime))s")
    }
    
    // MARK: - File Metadata Event (NIP-94)
    
    func testBlossomWithFileMetadataEventE2E() async throws {
        NDKLogger.log(.info, category: .general, "🧪 Starting testBlossomWithFileMetadataEventE2E")
        
        // Create NDK instance with relays
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Add relays and connect
        for relay in testRelays {
            await ndk.addRelay(relay)
        }
        
        await ndk.connect()
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        XCTAssertGreaterThan(connected, 0, "Should connect to at least one relay")
        
        // Create and upload test image data
        let imageData = createTestImageData()
        let _ = "test-image-\(UUID().uuidString).png" // fileName not needed since we don't pass it
        
        NDKLogger.log(.info, category: .general, "Uploading image to Blossom...")
        
        let blobs = try await ndk.uploadToBlossom(
            data: imageData,
            mimeType: "image/png",
            servers: testBlossomServers
        )
        
        XCTAssertFalse(blobs.isEmpty, "Should have uploaded to at least one server")
        
        // Create file metadata event (NIP-94)
        guard let firstBlob = blobs.first else {
            XCTFail("No Blossom blob available")
            return
        }
        let blossomUrl = firstBlob.url
        
        NDKLogger.log(.info, category: .general, "Creating file metadata event...")
        
        let fileMetadata = try await NDKEventBuilder(ndk: ndk)
            .content("Test image from Blossom E2E")
            .kind(1063) // File metadata
            .tag(["url", blossomUrl])
            .tag(["m", "image/png"])
            .tag(["size", "\(imageData.count)"])
            .tag(["x", firstBlob.sha256])
            .tag(["ox", firstBlob.sha256])
            .build()
        
        // Publish the event
        let publishedRelays = try await ndk.publish(fileMetadata)
        XCTAssertGreaterThan(publishedRelays.count, 0, "Should publish to at least one relay")
        
        NDKLogger.log(.info, category: .general, "Published file metadata to \(publishedRelays.count) relays")
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Fetch the event back
        let filter = NDKFilter(
            authors: [fileMetadata.pubkey],
            kinds: [EventKind.fileMetadata],
            limit: 1
        )
        
        // Fetch using observe with maxAge for one-shot query
        let dataSource = ndk.observe(filter: filter, maxAge: 3600)
        let fetchedEvents = await dataSource.collect(timeout: 5.0)
        XCTAssertEqual(fetchedEvents.count, 1, "Should fetch our file metadata event")
        
        if let fetchedEvent = fetchedEvents.first {
            // Extract Blossom URL from event
            let urlTags = fetchedEvent.tags.filter { $0.name == "url" }
            XCTAssertFalse(urlTags.isEmpty, "Should have URL tags")
            
            if let urlTag = urlTags.first, urlTag.count > 1 {
                XCTAssertEqual(urlTag[1], blossomUrl, "URL should match uploaded Blossom URL")
                NDKLogger.log(.info, category: .general, "✅ Verified Blossom URL in file metadata event")
            }
        }
        
        NDKLogger.log(.info, category: .general, "✅ Blossom with file metadata E2E test completed")
        
        await ndk.disconnect()
    }
    
    // MARK: - List and Delete Operations
    
    func testBlossomListAndDeleteE2E() async throws {
        NDKLogger.log(.info, category: .general, "🧪 Starting testBlossomListAndDeleteE2E")
        
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        _ = try await signer.pubkey
        
        // Upload a test file first
        let testData = "Delete test - \(UUID().uuidString)".data(using: .utf8)!
        let _ = "delete-test-\(UUID().uuidString).txt" // fileName not needed
        
        NDKLogger.log(.info, category: .general, "Uploading test file for deletion...")
        
        let blobs = try await ndk.uploadToBlossom(
            data: testData,
            mimeType: "text/plain",
            servers: [testBlossomServers[0]] // Use single server for simplicity
        )
        
        guard let blob = blobs.first else {
            XCTFail("Failed to upload")
            return
        }
        let sha256 = blob.sha256
        
        NDKLogger.log(.debug, category: .general, "Uploaded file with SHA256: \(sha256)")
        
        // List blobs
        let blossomClient = ndk.blossomClient
        
        NDKLogger.log(.info, category: .general, "Listing user's blobs...")
        
        do {
            // Create list auth
            let listAuth = try await BlossomAuth.createListAuth(
                signer: signer,
                ndk: ndk,
                since: Date().addingTimeInterval(-3600) // Last hour
            )
            
            let blobs = try await blossomClient.list(
                from: testBlossomServers[0],
                auth: listAuth,
                since: Date().addingTimeInterval(-3600) // Last hour
            )
            
            NDKLogger.log(.info, category: .general, "Found \(blobs.count) blobs")
            
            // Verify our blob is in the list
            let ourBlob = blobs.first { $0.sha256 == sha256 }
            XCTAssertNotNil(ourBlob, "Our uploaded blob should be in the list")
            
            if let blob = ourBlob {
                NDKLogger.log(.debug, category: .general, "Found our blob: \(blob.sha256), size: \(blob.size)")
            }
            
        } catch {
            NDKLogger.log(.warning, category: .general, "List operation failed (server may not support it): \(error)")
            // Some servers don't support list operation, so we continue
        }
        
        // Delete the blob
        NDKLogger.log(.info, category: .general, "Deleting blob...")
        
        do {
            // Create delete auth
            let deleteAuth = try await BlossomAuth.createDeleteAuth(
                sha256: sha256,
                signer: signer,
                ndk: ndk,
                reason: "E2E test cleanup"
            )
            
            try await blossomClient.delete(
                sha256: sha256,
                from: testBlossomServers[0],
                auth: deleteAuth
            )
            NDKLogger.log(.info, category: .general, "✅ Blob deleted successfully")
            
            // Verify deletion by trying to download
            NDKLogger.log(.info, category: .general, "Verifying deletion...")
            
            do {
                _ = try await blossomClient.download(sha256: sha256, from: testBlossomServers[0])
                XCTFail("Blob should not be downloadable after deletion")
            } catch {
                NDKLogger.log(.info, category: .general, "✅ Confirmed blob is deleted (download failed as expected)")
            }
            
        } catch {
            NDKLogger.log(.warning, category: .general, "Delete operation failed (server may not support it): \(error)")
            // Some servers don't support delete operation
        }
        
        NDKLogger.log(.info, category: .general, "✅ List and delete E2E test completed")
    }
    
    // MARK: - Multi-Server Upload with Failures
    
    func testBlossomMultiServerUploadE2E() async throws {
        NDKLogger.log(.info, category: .general, "🧪 Starting testBlossomMultiServerUploadE2E")
        
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Use a mix of valid and invalid servers
        let servers = [
            testBlossomServers[0],
            "https://invalid-blossom-server.example.com", // This should fail
            testBlossomServers[1]
        ]
        
        // Create larger test data
        let testContent = String(repeating: "Multi-server test data. ", count: 100)
        let testData = testContent.data(using: .utf8)!
        let _ = "multi-test-\(UUID().uuidString).txt" // fileName not needed
        
        NDKLogger.log(.info, category: .general, "Uploading to multiple servers (including invalid)...")
        
        let blobs = try await ndk.uploadToBlossom(
            data: testData,
            mimeType: "text/plain", 
            servers: servers
        )
        
        // Should have some successful uploads
        XCTAssertFalse(blobs.isEmpty, "Should have at least one successful upload")
        // We can't check exact count vs servers because uploadToBlossom returns successful blobs only
        
        NDKLogger.log(.info, category: .general, "✅ Uploaded \(blobs.count) blobs")
        
        // Verify redundancy - download from each successful blob
        for blob in blobs {
            NDKLogger.log(.debug, category: .general, "Verifying download of \(blob.sha256)...")
            
            // Extract server from URL
            if let url = URL(string: blob.url),
               let host = url.host,
               let scheme = url.scheme {
                let serverUrl = "\(scheme)://\(host)"
                
                let downloadedData = try await ndk.blossomClient.download(sha256: blob.sha256, from: serverUrl)
                
                let downloadedContent = String(data: downloadedData, encoding: .utf8)
                XCTAssertEqual(downloadedContent, testContent, "Content should match")
                
                NDKLogger.log(.debug, category: .general, "✅ Verified content from \(serverUrl)")
            }
        }
        
        NDKLogger.log(.info, category: .general, "✅ Multi-server upload E2E test completed")
    }
    
    // MARK: - Helper Methods
    
    private func extractSHA256FromBlossomURL(_ url: String) -> String? {
        // Blossom URLs typically end with the SHA256 hash
        // e.g., https://blossom.primal.net/abc123...def789
        guard let lastComponent = URL(string: url)?.lastPathComponent,
              lastComponent.count == 64 else { // SHA256 is 64 hex characters
            return nil
        }
        return lastComponent
    }
    
    
    private func createTestImageData() -> Data {
        // Create a simple 1x1 pixel PNG for testing
        let pngHeader: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        let ihdr: [UInt8] = [
            0, 0, 0, 13, // Length
            73, 72, 68, 82, // "IHDR"
            0, 0, 0, 1, // Width: 1
            0, 0, 0, 1, // Height: 1
            8, // Bit depth
            2, // Color type: RGB
            0, // Compression
            0, // Filter
            0, // Interlace
            13, 118, 182, 81 // CRC
        ]
        let idat: [UInt8] = [
            0, 0, 0, 12, // Length
            73, 68, 65, 84, // "IDAT"
            8, 29, 1, 1, 0, 0, 254, 255, 0, 0, 0, 2, // Compressed data
            177, 233, 67, 179 // CRC
        ]
        let iend: [UInt8] = [
            0, 0, 0, 0, // Length
            73, 69, 78, 68, // "IEND"
            174, 66, 96, 130 // CRC
        ]
        
        var data = Data()
        data.append(contentsOf: pngHeader)
        data.append(contentsOf: ihdr)
        data.append(contentsOf: idat)
        data.append(contentsOf: iend)
        return data
    }
}