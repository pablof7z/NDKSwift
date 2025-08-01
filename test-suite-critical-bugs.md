# Critical Bugs Found in Test Suite

## 1. NIP92 Automatic imeta Extraction Creates Duplicates

### Issue
When using manual `imetaTag()` methods in NDKEventBuilder, the automatic imeta extraction from content still occurs, creating duplicate imeta tags for the same URL.

### Details
- The `content()` method with `extractImeta: true` (default) automatically creates imeta tags for media URLs
- When manually adding imeta tags with `imetaTag()`, it doesn't check if an imeta tag already exists for that URL
- This results in duplicate imeta tags in the event

### Example
```swift
let event = try await NDKEventBuilder(ndk: ndk)
    .content("Photo: https://example.com/photo.jpg") // Creates automatic imeta tag
    .imetaTag(url: "https://example.com/photo.jpg") { imeta in // Creates another imeta tag
        imeta.alt = "Custom description"
    }
    .build()

// Result: 2 imeta tags for the same URL instead of 1
```

### Affected Tests
- `testManualImetaTag` - expects 1 tag, gets 2
- `testBlossomIntegration` - expects 1 tag, gets 2  
- `testNoDuplicateImetaTags` - expects 1 tag, gets 2
- `testPreConfiguredImetaTag` - expects 1 tag, gets 2
- `testBlossomIntegrationWithoutMetadata` - expects 1 tag, gets 2
- `testBlossomUploadWithPartialMetadata` - expects 1 tag, gets 2

### Root Cause
The NDKEventBuilder implementation in `imetaTag()` methods needs to:
1. Check if an imeta tag already exists for the URL (from automatic extraction)
2. Either replace the existing tag or skip adding a duplicate
3. The `hasImetaForURL()` method exists but may not be working correctly

### Severity
MAJOR - This is a functional bug that affects the correctness of NIP-92 implementation. Events will have duplicate imeta tags which violates the expected behavior.

### Recommendation
This needs a proper fix in the NDKEventBuilder implementation to prevent duplicate imeta tags. The fix should:
1. Make `imetaTag()` methods check for existing tags before adding
2. Replace existing auto-generated tags when manual tags are added
3. Ensure the deduplication logic works correctly

## 2. Test Suite Timeout Issues

### Issue
Many E2E tests hang forever when they can't connect to relays, and the timeout mechanisms don't work properly.

### Details
- Tests in DisabledTests folder were disabled due to hanging issues
- The `RawLoggingIntegrationTests` has a FIXME comment about hanging forever
- Timeout helpers exist but don't seem to prevent tests from hanging indefinitely

### Example
```swift
// From RawLoggingIntegrationTests.swift
// FIXME: This test hangs forever when it can't connect to relays
// The timeout mechanism doesn't seem to work properly
```

### Severity
MODERATE - Makes the test suite unreliable and difficult to run in CI/CD environments

### Recommendation
- Implement proper test timeouts at the XCTest level
- Use XCTestExpectation with proper timeout values
- Consider using mock relays for tests instead of real network connections