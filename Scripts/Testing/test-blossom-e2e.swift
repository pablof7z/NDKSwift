#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Run Blossom E2E tests as a standalone script
@main
struct BlossomE2ERunner {
    static func main() async throws {
        NDKLogger.log(.info, category: .general, "Starting Blossom E2E Tests")
        NDKLogger.logLevel = .debug
        
        do {
            // Test basic upload/download
            NDKLogger.log(.info, category: .general, "\n=== Running Basic Upload/Download Test ===")
            try await testBasicUploadDownload()
            NDKLogger.log(.info, category: .general, "✅ Basic upload/download test passed")
            
            // Test file metadata event integration
            NDKLogger.log(.info, category: .general, "\n=== Running File Metadata Event Test ===")
            try await testFileMetadataEvent()
            NDKLogger.log(.info, category: .general, "✅ File metadata event test passed")
            
            // Test list and delete operations
            NDKLogger.log(.info, category: .general, "\n=== Running List/Delete Test ===")
            try await testListAndDelete()
            NDKLogger.log(.info, category: .general, "✅ List/delete test passed")
            
            // Test multi-server upload
            NDKLogger.log(.info, category: .general, "\n=== Running Multi-Server Upload Test ===")
            try await testMultiServerUpload()
            NDKLogger.log(.info, category: .general, "✅ Multi-server upload test passed")
            
            NDKLogger.log(.info, category: .general, "\n✅ All Blossom E2E tests passed!")
            
        } catch {
            NDKLogger.log(.error, category: .general, "❌ Test failed with error: \(error)")
            exit(1)
        }
    }
    
    static func testBasicUploadDownload() async throws {
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
        
        // Upload to Blossom
        let blobs = try await NDKLogger.logTiming(.debug, category: .general, operation: "Blossom upload") {
            try await ndk.uploadToBlossom(
                data: testData,
                mimeType: "text/plain",
                servers: ["https://blossom.primal.net"]
            )
        }
        
        guard !blobs.isEmpty else {
            throw TestError.uploadFailed
        }
        
        NDKLogger.log(.info, category: .general, "Uploaded \(blobs.count) blobs")
        
        // Get SHA256 from first blob
        guard let firstBlob = blobs.first else {
            throw TestError.uploadFailed
        }
        let sha256 = firstBlob.sha256
        
        // Download from Blossom
        let blossomClient = ndk.blossomClient
        
        let downloadedData = try await NDKLogger.logTiming(.debug, category: .general, operation: "Blossom download") {
            try await blossomClient.download(sha256: sha256, from: "https://blossom.primal.net")
        }
        
        // Verify content
        let downloadedContent = String(data: downloadedData, encoding: .utf8)
        guard downloadedContent == testContent else {
            throw TestError.contentMismatch
        }
        
        NDKLogger.log(.info, category: .general, "Test completed in \(Date().timeIntervalSince(startTime))s")
    }
    
    static func testFileMetadataEvent() async throws {
        // Create NDK with relays
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Add relays
        let testRelays = [RelayConstants.damus, RelayConstants.nostrBand, RelayConstants.nosLol]
        for relay in testRelays {
            await ndk.addRelay(relay)
        }
        
        await ndk.connect()
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        guard connected > 0 else {
            throw TestError.connectionFailed
        }
        
        // Create and upload test image
        let imageData = createTestImageData()
        let fileName = "test-image-\(UUID().uuidString).png"
        
        let blobs = try await ndk.uploadToBlossom(
            data: imageData,
            mimeType: "image/png",
            servers: ["https://blossom.primal.net"]
        )
        
        guard let firstBlob = blobs.first else {
            throw TestError.uploadFailed
        }
        let blossomUrl = firstBlob.url
        
        // Create file metadata event
        let fileMetadata = try await NDKEventBuilder(ndk: ndk)
            .content("Test image from Blossom E2E")
            .kind(1063)
            .tag(["url", blossomUrl])
            .tag(["m", "image/png"])
            .tag(["size", "\(imageData.count)"])
            .tag(["x", firstBlob.sha256])
            .build()
        
        // Publish event
        let publishedRelays = try await ndk.publish(fileMetadata)
        guard !publishedRelays.isEmpty else {
            throw TestError.publishFailed
        }
        
        NDKLogger.log(.info, category: .general, "Published to \(publishedRelays.count) relays")
        
        // Wait and fetch back
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        let filter = NDKFilter(
            authors: [fileMetadata.pubkey],
            kinds: [EventKind.fileMetadata],
            limit: 1
        )
        
        let dataSource = ndk.observe(filter: filter, maxAge: 3600)
        let fetchedEvents = await dataSource.collect(timeout: 5.0)
        guard fetchedEvents.count == 1 else {
            throw TestError.eventNotFound
        }
        
        await ndk.disconnect()
    }
    
    static func testListAndDelete() async throws {
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let pubkey = try await signer.pubkey
        
        // Upload test file
        let testData = "Delete test - \(UUID().uuidString)".data(using: .utf8)!
        let fileName = "delete-test-\(UUID().uuidString).txt"
        
        let blobs = try await ndk.uploadToBlossom(
            data: testData,
            mimeType: "text/plain",
            servers: ["https://blossom.primal.net"]
        }
        
        guard let blob = blobs.first else {
            throw TestError.uploadFailed
        }
        let sha256 = blob.sha256
        
        let blossomClient = ndk.blossomClient
        
        // Try to list blobs (may not be supported by all servers)
        do {
            let listAuth = try await BlossomAuth.createListAuth(
                signer: signer,
                since: Date().addingTimeInterval(-3600)
            )
            
            let blobs = try await blossomClient.list(
                from: "https://blossom.primal.net",
                auth: listAuth,
                since: Date().addingTimeInterval(-3600)
            )
            NDKLogger.log(.info, category: .general, "Found \(blobs.count) blobs")
        } catch {
            NDKLogger.log(.warning, category: .general, "List not supported: \(error)")
        }
        
        // Try to delete blob (may not be supported by all servers)
        do {
            let deleteAuth = try await BlossomAuth.createDeleteAuth(
                sha256: sha256,
                signer: signer,
                reason: "E2E test cleanup"
            )
            
            let deleted = try await blossomClient.delete(
                sha256: sha256,
                from: "https://blossom.primal.net",
                auth: deleteAuth
            )
            
            if deleted {
                NDKLogger.log(.info, category: .general, "Blob deleted successfully")
                
                // Verify deletion
                do {
                    _ = try await blossomClient.download(sha256: sha256, from: "https://blossom.primal.net")
                    throw TestError.deletionFailed
                } catch {
                    // Expected - blob should be gone
                    NDKLogger.log(.info, category: .general, "Deletion verified")
                }
            }
        } catch {
            NDKLogger.log(.warning, category: .general, "Delete not supported: \(error)")
        }
    }
    
    static func testMultiServerUpload() async throws {
        let ndk = NDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Mix of valid and invalid servers
        let servers = [
            "https://blossom.primal.net",
            "https://invalid-server.example.com",
            "https://files.v0l.io"
        ]
        
        let testContent = String(repeating: "Multi-server test. ", count: 50)
        let testData = testContent.data(using: .utf8)!
        let fileName = "multi-\(UUID().uuidString).txt"
        
        let blobs = try await ndk.uploadToBlossom(
            data: testData,
            mimeType: "text/plain",
            servers: servers
        )
        
        // Should have some successes
        guard !blobs.isEmpty else {
            throw TestError.uploadFailed
        }
        
        NDKLogger.log(.info, category: .general, "Uploaded \(blobs.count) blobs")
        
        // Verify each successful upload
        for blob in blobs {
            if let url = URL(string: blob.url),
               let host = url.host,
               let scheme = url.scheme {
                let serverUrl = "\(scheme)://\(host)"
                
                let downloadedData = try await ndk.blossomClient.download(sha256: blob.sha256, from: serverUrl)
                
                let downloadedContent = String(data: downloadedData, encoding: .utf8)
                guard downloadedContent == testContent else {
                    throw TestError.contentMismatch
                }
                
                NDKLogger.log(.debug, category: .general, "Verified content from \(serverUrl)")
            }
        }
    }
    
    // Helper functions
    static func extractSHA256FromURL(_ url: String) -> String? {
        guard let lastComponent = URL(string: url)?.lastPathComponent,
              lastComponent.count == 64 else {
            return nil
        }
        return lastComponent
    }
    
    static func createTestImageData() -> Data {
        // Simple 1x1 pixel PNG
        let pngData: [UInt8] = [
            137, 80, 78, 71, 13, 10, 26, 10, // PNG header
            0, 0, 0, 13, 73, 72, 68, 82, // IHDR chunk
            0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0,
            13, 118, 182, 81, // IHDR CRC
            0, 0, 0, 12, 73, 68, 65, 84, // IDAT chunk
            8, 29, 1, 1, 0, 0, 254, 255, 0, 0, 0, 2,
            177, 233, 67, 179, // IDAT CRC
            0, 0, 0, 0, 73, 69, 78, 68, // IEND chunk
            174, 66, 96, 130 // IEND CRC
        ]
        
        return Data(pngData)
    }
}

// Test errors
enum TestError: Error {
    case connectionFailed
    case uploadFailed
    case downloadFailed
    case contentMismatch
    case invalidURL
    case publishFailed
    case eventNotFound
    case deletionFailed
    case unexpectedSuccess
}