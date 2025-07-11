# ContentTagger Nostr Entity Tests Results

## Summary
All tests are passing! The ContentTagger correctly parses and tags nostr entities.

## Test Results

### 1. ✅ `testNeventGeneratesQTag`
- **Input**: `nostr:nevent1...`
- **Generated Tags**: 
  - `["q", "3fa020984203d3a5f10466b195927e4403065ea262daa2007b9c70e975454c80", "wss://relay.damus.io"]`
  - `["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]`
- **Status**: Correctly generates 'q' tag for event ID and 'p' tag for author

### 2. ✅ `testNprofileGeneratesPTag`
- **Input**: `nostr:nprofile1...`
- **Generated Tags**: 
  - `["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]`
- **Status**: Correctly generates 'p' tag for profile

### 3. ✅ `testNaddrGeneratesQAndPTags`
- **Input**: `nostr:naddr1...`
- **Generated Tags**:
  - `["q", "30023:3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d:test-article", "wss://relay.damus.io"]`
  - `["p", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]`
- **Status**: Correctly generates 'q' tag with kind:pubkey:identifier format and 'p' tag for author

### 4. ✅ `testMultipleEntitiesInContent`
- **Input**: Multiple nostr entities (nevent, nprofile, naddr, npub)
- **Generated Tags**: 4 tags total (2 'q' tags, 2 'p' tags)
- **Status**: Correctly processes multiple entities and deduplicates tags

### 5. ✅ `testAtMentionFormat`
- **Input**: `@npub1...`
- **Output**: Converts to `nostr:npub1...`
- **Generated Tags**: `["p", "..."]`
- **Status**: Correctly converts @ mentions to nostr: format

### 6. ✅ `testInvalidBech32HandledGracefully`
- **Input**: Invalid bech32 strings
- **Generated Tags**: None
- **Status**: Gracefully handles invalid entities without crashing

### 7. ✅ `testHashtagsAlongWithNostrEntities`
- **Input**: Content with both nostr entities and hashtags
- **Generated Tags**: Both 'q' tags and 't' tags (hashtags in lowercase)
- **Status**: Correctly processes both entity types

### 8. ✅ `testParseContentSegments`
- **Input**: Mixed content with text, mentions, events, and hashtags
- **Output**: Correctly segmented into different types
- **Status**: ParseContentSegments function correctly identifies all segment types

## Key Findings

1. **Bech32 Validation**: The ContentTagger properly validates bech32 checksums and rejects invalid entities
2. **Tag Generation**: 
   - 'p' tags are generated for npub, nprofile, and author references in nevent/naddr
   - 'q' tags are generated for note, nevent, and naddr entities
   - Relay URLs are included in 'q' tags when available
3. **Format Normalization**: @ mentions are converted to nostr: format
4. **Deduplication**: Duplicate tags are properly removed
5. **Hashtag Processing**: Hashtags are converted to lowercase as per NIP-24

## Implementation Details

The ContentTagger uses:
- Regular expressions to find nostr entities in content
- Bech32 decoding to extract data from entities
- TLV (Type-Length-Value) decoding for complex entities (nevent, nprofile, naddr)
- Tag deduplication to avoid redundant tags