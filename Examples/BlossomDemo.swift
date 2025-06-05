#!/usr/bin/env swift

import Foundation
import NDKSwift

// MARK: - Blossom Demo

// This demo shows how to use NDKSwift's Blossom support for decentralized file storage

@main
struct BlossomDemo {
    static func main() async {
        print("🌸 NDKSwift Blossom Demo")
        print("========================\n")

        do {
            // Initialize NDK
            let ndk = NDK()

            // Create a signer
            let signer = NDKPrivateKeySigner.generate()
            ndk.signer = signer

            print("📝 Created signer with pubkey: \(signer.publicKey)")

            // MARK: - Basic Upload Example

            print("\n1️⃣ Basic File Upload")
            print("---------------------")

            let testData = "Hello, Blossom! This is a test file.".data(using: .utf8)!
            let blossomClient = ndk.blossomClient

            // Upload with auth
            do {
                let blob = try await blossomClient.uploadWithAuth(
                    data: testData,
                    mimeType: "text/plain",
                    to: "https://blossom.example.com",
                    signer: signer
                )

                print("✅ Uploaded successfully!")
                print("   URL: \(blob.url)")
                print("   SHA256: \(blob.sha256)")
                print("   Size: \(blob.size) bytes")
            } catch {
                print("❌ Upload failed: \(error)")
            }

            // MARK: - Image Upload with NDK Integration

            print("\n2️⃣ Image Upload with Event Creation")
            print("------------------------------------")

            // Create sample image data (in real app, load from file or camera)
            let imageData = createSampleImageData()

            do {
                // Upload to multiple Blossom servers
                let blobs = try await ndk.uploadToBlossom(
                    data: imageData,
                    mimeType: "image/png",
                    servers: [
                        "https://blossom.primal.net",
                        "https://media.nostr.band",
                    ]
                )

                print("✅ Uploaded to \(blobs.count) server(s)")
                for blob in blobs {
                    print("   - \(blob.url)")
                }

                // Create an image event
                let imageEvent = try await NDKEvent.createImageEvent(
                    imageData: imageData,
                    mimeType: "image/png",
                    caption: "A beautiful sunset 🌅",
                    ndk: ndk
                )

                print("\n📸 Created image event:")
                print("   Event ID: \(imageEvent.id ?? "pending")")
                print("   Kind: \(imageEvent.kind)")

                // Show imeta tags
                if let imetaTag = imageEvent.tags.first(where: { $0.first == "imeta" }) {
                    print("   Imeta: \(imetaTag.dropFirst().joined(separator: " "))")
                }
            } catch {
                print("❌ Image upload failed: \(error)")
            }

            // MARK: - File Metadata Event

            print("\n3️⃣ File Metadata Event (NIP-94)")
            print("--------------------------------")

            // Create a file metadata event
            let pdfData = "Sample PDF content".data(using: .utf8)!

            do {
                let pdfBlobs = try await ndk.uploadToBlossom(
                    data: pdfData,
                    mimeType: "application/pdf"
                )

                let metadataEvent = try await NDKEvent.createFileMetadata(
                    blobs: pdfBlobs,
                    description: "Important document about Nostr protocol",
                    signer: signer
                )

                print("📄 Created file metadata event:")
                print("   Event kind: \(metadataEvent.kind)")
                print("   URLs: \(metadataEvent.extractBlossomURLs().count)")

                for (url, sha256) in metadataEvent.extractBlossomURLs() {
                    print("   - URL: \(url)")
                    print("     SHA256: \(sha256)")
                }
            } catch {
                print("❌ File metadata creation failed: \(error)")
            }

            // MARK: - List Blobs

            print("\n4️⃣ List User's Blobs")
            print("--------------------")

            do {
                let blobs = try await blossomClient.listWithAuth(
                    from: "https://blossom.example.com",
                    signer: signer
                )

                print("📋 Found \(blobs.count) blob(s):")
                for blob in blobs {
                    print("   - \(blob.sha256) (\(blob.size) bytes)")
                    if let type = blob.type {
                        print("     Type: \(type)")
                    }
                    print("     Uploaded: \(blob.uploaded)")
                }
            } catch {
                print("❌ List failed: \(error)")
            }

            // MARK: - Download Blob

            print("\n5️⃣ Download Blob")
            print("-----------------")

            let testSHA256 = "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"

            do {
                let downloadedData = try await blossomClient.download(
                    sha256: testSHA256,
                    from: "https://blossom.example.com"
                )

                if let content = String(data: downloadedData, encoding: .utf8) {
                    print("✅ Downloaded content: \(content)")
                } else {
                    print("✅ Downloaded \(downloadedData.count) bytes")
                }
            } catch {
                print("❌ Download failed: \(error)")
            }

            // MARK: - Delete Blob

            print("\n6️⃣ Delete Blob")
            print("---------------")

            do {
                try await blossomClient.deleteWithAuth(
                    sha256: testSHA256,
                    from: "https://blossom.example.com",
                    signer: signer,
                    reason: "No longer needed"
                )

                print("✅ Blob deleted successfully")
            } catch {
                print("❌ Delete failed: \(error)")
            }

            // MARK: - Server Discovery

            print("\n7️⃣ Server Discovery")
            print("-------------------")

            do {
                let descriptor = try await blossomClient.discoverServer("https://blossom.example.com")

                print("🔍 Server information:")
                if let name = descriptor.name {
                    print("   Name: \(name)")
                }
                if let description = descriptor.description {
                    print("   Description: \(description)")
                }
                if let mimeTypes = descriptor.acceptsMimeTypes {
                    print("   Accepted types: \(mimeTypes.joined(separator: ", "))")
                }
                if let maxSize = descriptor.maxUploadSize {
                    print("   Max file size: \(formatBytes(maxSize))")
                }
            } catch {
                print("❌ Server discovery failed: \(error)")
            }

            print("\n✨ Blossom demo completed!")

        } catch {
            print("❌ Fatal error: \(error)")
        }
    }

    // Helper function to create sample image data
    static func createSampleImageData() -> Data {
        // In a real app, this would load an actual image
        // For demo purposes, we'll create a tiny valid PNG
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, // IHDR chunk length
            0x49, 0x48, 0x44, 0x52, // IHDR
            0x00, 0x00, 0x00, 0x01, // width: 1
            0x00, 0x00, 0x00, 0x01, // height: 1
            0x08, 0x02, // bit depth: 8, color type: 2 (RGB)
            0x00, 0x00, 0x00, // compression, filter, interlace
            0x90, 0x77, 0x53, 0xDE, // CRC
            0x00, 0x00, 0x00, 0x0C, // IDAT chunk length
            0x49, 0x44, 0x41, 0x54, // IDAT
            0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x03, 0x01, 0x01, 0x00, // compressed data
            0x18, 0xDD, 0x8D, 0xB4, // CRC
            0x00, 0x00, 0x00, 0x00, // IEND chunk length
            0x49, 0x45, 0x4E, 0x44, // IEND
            0xAE, 0x42, 0x60, 0x82, // CRC
        ]
        return Data(pngHeader)
    }

    // Helper function to format bytes
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Usage Instructions

/*
 To run this demo:

 1. Make sure you're in the NDKSwift directory
 2. Run: swift run BlossomDemo

 Or compile and run:
 1. swiftc -o blossom-demo Examples/BlossomDemo.swift -I .build/debug -L .build/debug -lNDKSwift
 2. ./blossom-demo

 Note: This demo uses example URLs. In production, use real Blossom servers like:
 - https://blossom.primal.net
 - https://media.nostr.band
 - https://nostr.build
 */
