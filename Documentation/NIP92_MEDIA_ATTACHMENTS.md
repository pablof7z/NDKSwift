# NIP-92 Media Attachments

NDKSwift provides comprehensive support for NIP-92 media attachments through the `imeta` tag system. This allows you to attach metadata to media URLs in your Nostr events.

## Overview

NIP-92 defines the `imeta` tag for adding metadata to media files referenced in event content. NDKSwift makes this easy with:

- **Automatic URL extraction** - Media URLs in content automatically get `imeta` tags
- **Manual control** - Add custom metadata when needed
- **Blossom integration** - First-class support for Blossom file uploads
- **Type-safe API** - No manual tag array construction

## Basic Usage

### Automatic Media URL Extraction (Default)

By default, NDKSwift automatically extracts media URLs from your content and creates `imeta` tags:

```swift
let event = try await ndk.event()
    .content("Check out this photo: https://example.com/sunset.jpg")
    .build()

// Automatically creates: ["imeta", "url https://example.com/sunset.jpg"]
```

Supported media extensions:
- Images: `jpg`, `jpeg`, `png`, `gif`, `webp`, `bmp`, `svg`
- Videos: `mp4`, `webm`, `mov`, `avi`, `mkv`, `flv`, `wmv`, `m4v`
- Audio: `mp3`, `m4a`, `ogg`, `wav`, `flac`, `aac`, `opus`
- Documents: `pdf`

### Disable Automatic Extraction

When you need full control over `imeta` tags:

```swift
let event = try await ndk.event()
    .content("URL that won't get imeta: https://github.com/image.png", extractImeta: false)
    .build()
```

## Adding Custom Metadata

### Basic Custom Metadata

Enhance automatically extracted URLs with additional metadata:

```swift
let event = try await ndk.event()
    .content("My vacation photo: https://example.com/beach.jpg")
    .imetaTag(url: "https://example.com/beach.jpg") { imeta in
        imeta.alt = "Sunset at the beach in Costa Rica"
        imeta.dim = "3024x4032"
        imeta.m = "image/jpeg"
        imeta.blurhash = "eVF$^OI:${M{o#*0-nNFxakD"
    }
    .build()
```

### Pre-configured Imeta Tag

Create and reuse imeta configurations:

```swift
var imeta = NDKImetaTag()
imeta.url = "https://example.com/photo.jpg"
imeta.alt = "Product photo"
imeta.dim = "800x600"
imeta.fallback = ["https://backup1.com/photo.jpg", "https://backup2.com/photo.jpg"]

let event = try await ndk.event()
    .content("New product: https://example.com/photo.jpg")
    .imetaTag(imeta)
    .build()
```

## Blossom Integration

NDKSwift provides seamless integration with Blossom file uploads, **automatically extracting blurhash and dimensions** during upload:

```swift
// Upload file to Blossom
let imageData = UIImage(named: "photo")!.jpegData(compressionQuality: 0.8)!
let upload = try await ndk.uploadToBlossom(data: imageData, mimeType: "image/jpeg")

// Create event with Blossom metadata
let event = try await ndk.event()
    .content("Just uploaded: \(upload.first!.url)")
    .imetaTag(from: upload.first!)  // Includes all metadata automatically!
    .build()
```

The Blossom integration **automatically** includes:
- URL from the upload
- SHA256 hash (`x` field)
- File size
- MIME type (auto-detected if not provided)
- **Blurhash** (calculated during upload for images)
- **Dimensions** (extracted during upload for images)

### Automatic Metadata Extraction

When you upload an image to Blossom, NDKSwift automatically:

1. **Detects MIME type** from file signature if not provided
2. **Calculates blurhash** for supported image formats (JPEG, PNG, WebP, HEIC)
3. **Extracts dimensions** from the image data
4. **Includes all metadata** in the returned `BlossomBlob`

This means your `imeta` tags are complete without any extra work:

```swift
// The upload result contains:
upload.first!.url         // "https://blossom.example.com/abc123..."
upload.first!.sha256      // "abc123def456..."
upload.first!.size        // 512000
upload.first!.type        // "image/jpeg"
upload.first!.blurhash    // "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."
upload.first!.dimensions  // (width: 3024, height: 4032)
```

## Available Imeta Fields

The `NDKImetaTag` struct supports all NIP-92 fields:

- `url` (required): The media URL
- `m`: MIME type (e.g., "image/jpeg")
- `alt`: Alternative text description
- `dim`: Dimensions as "widthxheight" (e.g., "1920x1080")
- `blurhash`: Blur hash for placeholder images
- `x`: SHA256 hash of the file
- `size`: File size in bytes
- `fallback`: Array of fallback URLs
- `additionalFields`: Dictionary for any custom fields

## Advanced Examples

### Mix Automatic and Manual

Start with automatic extraction, then enhance specific URLs:

```swift
let event = try await ndk.event()
    .content("Photos: https://example.com/1.jpg and https://example.com/2.jpg")
    .imetaTag(url: "https://example.com/1.jpg") { imeta in
        imeta.alt = "Main photo with description"
        imeta.dim = "1920x1080"
    }
    // Second URL gets basic automatic imeta tag
    .build()
```

### Multiple Media Types

```swift
let event = try await ndk.event()
    .content("""
        Check out my content:
        Video: https://example.com/tutorial.mp4
        Audio: https://example.com/podcast.mp3
        Document: https://example.com/guide.pdf
        """)
    .imetaTag(url: "https://example.com/tutorial.mp4") { imeta in
        imeta.m = "video/mp4"
        imeta.dim = "1280x720"
        imeta.alt = "Tutorial on Nostr development"
    }
    .build()
```

### With Fallback URLs

```swift
let event = try await ndk.event()
    .content("Important image: https://primary.com/critical.jpg")
    .imetaTag(url: "https://primary.com/critical.jpg") { imeta in
        imeta.fallback = [
            "https://backup1.com/critical.jpg",
            "https://backup2.com/critical.jpg",
            "https://ipfs.io/ipfs/QmXxx..."
        ]
        imeta.alt = "Critical diagram - multiple backups available"
    }
    .build()
```

## Best Practices

1. **Let automatic extraction handle common cases** - The default behavior covers most use cases
2. **Add alt text for accessibility** - Always include alternative text for images
3. **Include dimensions for images** - Helps clients reserve space while loading
4. **Use Blossom for decentralized storage** - Integrates seamlessly with `imetaTag(from:)`
5. **Provide fallback URLs for critical content** - Ensures availability across different hosting providers

## Extracting Imeta Tags from Events

NDKSwift provides convenient extensions to extract and work with imeta tags from existing events:

```swift
// Get all imeta tags from an event
let imetaTags = event.imetas

// Check if event has any imeta tags
if event.hasImeta {
    print("Event contains \(event.imetas.count) media attachments")
}

// Get imeta tags for a specific URL
let specificTags = event.imetas(for: "https://example.com/photo.jpg")

// Get the first imeta tag
if let firstImeta = event.firstImeta {
    print("First media URL: \(firstImeta.url ?? "")")
}

// Get all media URLs
let allURLs = event.imetaURLs

// Get imeta tags by MIME type
let imetasByType = event.imetasByMimeType
let imageImetas = imetasByType["image/jpeg"] ?? []

// Convenience properties for specific media types
let images = event.imageImetas
let videos = event.videoImetas  
let audio = event.audioImetas

// Get primary image metadata
if let dimensions = event.primaryImageDimensions {
    print("Primary image: \(dimensions.width)x\(dimensions.height)")
}
if let blurhash = event.primaryImageBlurhash {
    print("Blurhash: \(blurhash)")
}
if let primaryURL = event.primaryImageURL {
    print("Primary image URL: \(primaryURL)")
}

// Get all image URLs
let allImageURLs = event.imageURLs
```

## Migration Guide

If you're already creating events with media URLs, no changes are needed! NDKSwift now automatically adds basic `imeta` tags. To enhance your media with additional metadata, simply add `.imetaTag()` calls to your event builder chain.