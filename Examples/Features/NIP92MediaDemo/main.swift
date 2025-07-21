import Foundation
import NDKSwift

// NIP-92 Media Attachments Demo
// This example demonstrates how to use NIP-92 imeta tags for media attachments

@main
struct NIP92MediaDemo {
    static func main() async throws {
        // Initialize NDK
        let ndk = NDK()
        
        // Configure with a test private key
        let privateKey = NDKPrivateKey.generate()
        ndk.signer = NDKPrivateKeySigner(privateKey: privateKey)
        
        print("NIP-92 Media Attachments Demo")
        print("============================\n")
        
        // Example 1: Automatic imeta tag extraction
        print("1. Automatic media URL extraction:")
        let event1 = try await ndk.event()
            .content("Check out these photos: https://example.com/sunset.jpg and https://example.com/beach.png")
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event1.content)")
        print("Generated imeta tags:")
        for tag in event1.tags where tag.first == "imeta" {
            print("  \(tag)")
        }
        print()
        
        // Example 2: Manual imeta tag with additional metadata
        print("2. Manual imeta tag with metadata:")
        let event2 = try await ndk.event()
            .content("My vacation photo: https://example.com/vacation.jpg")
            .imetaTag(url: "https://example.com/vacation.jpg") { imeta in
                imeta.alt = "Beautiful sunset at the beach in Costa Rica"
                imeta.dim = "3024x4032"
                imeta.m = "image/jpeg"
                imeta.blurhash = "eVF$^OI:${M{o#*0-nNFxakD-?xVM}WEWB%iNKxvR-oetmo#R-aen$"
            }
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event2.content)")
        print("Generated imeta tags:")
        for tag in event2.tags where tag.first == "imeta" {
            print("  \(tag)")
        }
        print()
        
        // Example 3: Disable automatic extraction
        print("3. Disable automatic imeta extraction:")
        let event3 = try await ndk.event()
            .content("This URL won't get an imeta tag: https://github.com/image.png", extractImeta: false)
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event3.content)")
        print("Number of imeta tags: \(event3.tags.filter { $0.first == "imeta" }.count)")
        print()
        
        // Example 4: Mix automatic and manual
        print("4. Mix automatic extraction with manual enhancement:")
        let event4 = try await ndk.event()
            .content("Photos: https://example.com/photo1.jpg and https://example.com/photo2.jpg")
            .imetaTag(url: "https://example.com/photo1.jpg") { imeta in
                imeta.alt = "First photo with custom description"
                imeta.dim = "1920x1080"
            }
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event4.content)")
        print("Generated imeta tags:")
        for tag in event4.tags where tag.first == "imeta" {
            print("  \(tag)")
        }
        print()
        
        // Example 5: Blossom integration with automatic metadata extraction
        print("5. Blossom upload with automatic blurhash (simulated):")
        
        // Simulate a Blossom upload result with automatically extracted metadata
        let blossomUpload = BlossomBlob(
            sha256: "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3",
            url: "https://blossom.example.com/a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3.jpg",
            size: 1024 * 500, // 500KB
            type: "image/jpeg",
            uploaded: Date(),
            blurhash: "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.", // Automatically calculated during upload
            dimensions: (width: 3024, height: 4032) // Automatically extracted during upload
        )
        
        let event5 = try await ndk.event()
            .content("Just uploaded this photo: \(blossomUpload.url)")
            .imetaTag(from: blossomUpload) // Includes all metadata automatically
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event5.content)")
        print("Generated imeta tags (includes auto-extracted blurhash and dimensions):")
        for tag in event5.tags where tag.first == "imeta" {
            print("  \(tag)")
        }
        print()
        
        // Example 5b: Real Blossom upload (commented out as it requires actual image data)
        print("5b. Real Blossom upload example (code only):")
        print("""
        // In a real app:
        let imageData = UIImage(named: "photo")!.jpegData(compressionQuality: 0.8)!
        let upload = try await ndk.uploadToBlossom(data: imageData, mimeType: "image/jpeg")
        
        // The upload result now automatically includes:
        // - blurhash (calculated from the image)
        // - dimensions (extracted from the image)
        // - SHA256 hash
        // - file size
        
        let event = try await ndk.event()
            .content("Check out my photo: \\(upload.first!.url)")
            .imetaTag(from: upload.first!)
            .build()
        """)
        print()
        
        // Example 6: Multiple media types
        print("6. Multiple media types:")
        let event6 = try await ndk.event()
            .content("Check out my content: https://example.com/video.mp4, https://example.com/audio.mp3, and https://example.com/document.pdf")
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event6.content)")
        print("Generated imeta tags:")
        for tag in event6.tags where tag.first == "imeta" {
            print("  \(tag)")
        }
        print()
        
        // Example 7: Pre-configured imeta tag
        print("7. Pre-configured imeta tag:")
        var customImeta = NDKImetaTag()
        customImeta.url = "https://example.com/custom.jpg"
        customImeta.alt = "Custom configured image"
        customImeta.m = "image/jpeg"
        customImeta.dim = "800x600"
        customImeta.fallback = ["https://backup1.com/custom.jpg", "https://backup2.com/custom.jpg"]
        
        let event7 = try await ndk.event()
            .content("Image with fallback URLs: https://example.com/custom.jpg")
            .imetaTag(customImeta)
            .kind(EventKind.textNote)
            .build()
        
        print("Event content: \(event7.content)")
        print("Generated imeta tags:")
        for tag in event7.tags where tag.first == "imeta" {
            print("  \(tag)")
        }
        
        print("\nDemo completed!")
    }
}