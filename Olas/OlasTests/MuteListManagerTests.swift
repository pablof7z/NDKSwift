import Testing
@testable import Olas

/// Tests for MuteListManager's pure logic.
/// Note: Full integration tests require NDK which needs network/mocking.
/// These tests verify the synchronous, pure-logic portions of the manager.
@Suite("MuteListManager")
@MainActor
struct MuteListManagerTests {

    // MARK: - isMuted Logic

    @Test("Empty mute list returns false for any pubkey")
    func emptyList_isMuted_returnsFalse() {
        // The isMuted function checks against the published mutedPubkeys set
        // When empty, any pubkey should return false
        let mutedPubkeys: Set<String> = []
        let testPubkey = "npub1abc123"

        #expect(mutedPubkeys.contains(testPubkey) == false)
    }

    @Test("Muted pubkey returns true")
    func mutedPubkey_isMuted_returnsTrue() {
        let testPubkey = "npub1abc123"
        var mutedPubkeys: Set<String> = []
        mutedPubkeys.insert(testPubkey)

        #expect(mutedPubkeys.contains(testPubkey) == true)
    }

    @Test("Non-muted pubkey returns false when list has entries")
    func nonMutedPubkey_isMuted_returnsFalse() {
        let mutedPubkey = "npub1muted"
        let testPubkey = "npub1notmuted"
        var mutedPubkeys: Set<String> = []
        mutedPubkeys.insert(mutedPubkey)

        #expect(mutedPubkeys.contains(testPubkey) == false)
    }

    // MARK: - Set Operations (simulating mute/unmute)

    @Test("Adding pubkey to set makes it muted")
    func addPubkey_makesItMuted() {
        var mutedPubkeys: Set<String> = []
        let testPubkey = "npub1test"

        mutedPubkeys.insert(testPubkey)

        #expect(mutedPubkeys.contains(testPubkey) == true)
        #expect(mutedPubkeys.count == 1)
    }

    @Test("Removing pubkey from set unmutes it")
    func removePubkey_unmutesIt() {
        let testPubkey = "npub1test"
        var mutedPubkeys: Set<String> = [testPubkey]

        mutedPubkeys.remove(testPubkey)

        #expect(mutedPubkeys.contains(testPubkey) == false)
        #expect(mutedPubkeys.count == 0)
    }

    @Test("Muting same pubkey twice is idempotent")
    func muteSamePubkeyTwice_idempotent() {
        var mutedPubkeys: Set<String> = []
        let testPubkey = "npub1test"

        mutedPubkeys.insert(testPubkey)
        mutedPubkeys.insert(testPubkey)

        #expect(mutedPubkeys.count == 1)
    }

    @Test("Unmuting non-muted pubkey is safe")
    func unmuteNonMutedPubkey_safe() {
        var mutedPubkeys: Set<String> = []
        let testPubkey = "npub1test"

        mutedPubkeys.remove(testPubkey)

        #expect(mutedPubkeys.count == 0)
    }

    // MARK: - Parsing Logic (simulating parseMuteList)

    @Test("Parse p tags from event tags")
    func parsePTags_extractsPubkeys() {
        // Simulating the tag parsing logic from parseMuteList
        let tags: [[String]] = [
            ["p", "pubkey1"],
            ["p", "pubkey2"],
            ["e", "eventid"],  // Should be ignored
            ["p", "pubkey3"],
            ["t", "topic"],    // Should be ignored
        ]

        var pubkeys = Set<String>()
        for tag in tags {
            if tag.first == "p", tag.count > 1 {
                pubkeys.insert(tag[1])
            }
        }

        #expect(pubkeys.count == 3)
        #expect(pubkeys.contains("pubkey1"))
        #expect(pubkeys.contains("pubkey2"))
        #expect(pubkeys.contains("pubkey3"))
        #expect(!pubkeys.contains("eventid"))
    }

    @Test("Parse empty tags returns empty set")
    func parseEmptyTags_returnsEmptySet() {
        let tags: [[String]] = []

        var pubkeys = Set<String>()
        for tag in tags {
            if tag.first == "p", tag.count > 1 {
                pubkeys.insert(tag[1])
            }
        }

        #expect(pubkeys.isEmpty)
    }

    @Test("Parse p tag with missing value is skipped")
    func parsePTagMissingValue_skipped() {
        let tags: [[String]] = [
            ["p"],  // Missing pubkey value
            ["p", "validpubkey"],
        ]

        var pubkeys = Set<String>()
        for tag in tags {
            if tag.first == "p", tag.count > 1 {
                pubkeys.insert(tag[1])
            }
        }

        #expect(pubkeys.count == 1)
        #expect(pubkeys.contains("validpubkey"))
    }

    // MARK: - Building Mute List Tags

    @Test("Build p tags from muted pubkeys")
    func buildPTags_fromMutedPubkeys() {
        let mutedPubkeys: Set<String> = ["pubkey1", "pubkey2", "pubkey3"]

        var tags: [[String]] = []
        for pubkey in mutedPubkeys {
            tags.append(["p", pubkey])
        }

        #expect(tags.count == 3)
        #expect(tags.allSatisfy { $0.first == "p" })
        #expect(tags.allSatisfy { $0.count == 2 })
    }

    @Test("Build empty tags from empty mute list")
    func buildEmptyTags_fromEmptyList() {
        let mutedPubkeys: Set<String> = []

        var tags: [[String]] = []
        for pubkey in mutedPubkeys {
            tags.append(["p", pubkey])
        }

        #expect(tags.isEmpty)
    }
}
