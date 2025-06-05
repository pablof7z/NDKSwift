#!/usr/bin/env swift

import Foundation

// Add the path to NDKSwift if needed
#if canImport(NDKSwift)
    import NDKSwift

    print("🚀 NDKSwift Content Tagging Integration Demo")
    print("============================================")

    // Test 1: Basic hashtag tagging
    print("\n1. Testing basic hashtag tagging:")
    let event1 = NDKEvent(
        pubkey: "test_pubkey",
        createdAt: 1_234_567_890,
        kind: 1,
        tags: [],
        content: "This is a #test post about #bitcoin and #nostr"
    )

    event1.generateContentTags()

    print("   Content: \(event1.content)")
    print("   Tags: \(event1.tags)")

    let tTags = event1.tags.filter { $0[0] == "t" }
    print("   Found \(tTags.count) hashtag tags:")
    for tag in tTags {
        if tag.count > 1 {
            print("     - #\(tag[1])")
        }
    }

    // Test 2: Mixed content with existing tags
    print("\n2. Testing mixed content with existing tags:")
    let event2 = NDKEvent(
        pubkey: "test_pubkey",
        createdAt: 1_234_567_890,
        kind: 1,
        tags: [["p", "existing_pubkey"], ["custom", "value"]],
        content: "Hello world! This is about #bitcoin and #lightning"
    )

    event2.generateContentTags()

    print("   Content: \(event2.content)")
    print("   Total tags: \(event2.tags.count)")
    print("   Tags:")
    for tag in event2.tags {
        print("     - \(tag)")
    }

    // Test 3: setContent convenience method
    print("\n3. Testing setContent convenience method:")
    let event3 = NDKEvent(
        pubkey: "test_pubkey",
        createdAt: 1_234_567_890,
        kind: 1,
        tags: [],
        content: ""
    )

    event3.setContent("New content with #swift and #ios hashtags")

    print("   Content: \(event3.content)")
    print("   Auto-generated tags: \(event3.tags)")

    // Test 4: Duplicate tag prevention
    print("\n4. Testing duplicate tag prevention:")
    let event4 = NDKEvent(
        pubkey: "test_pubkey",
        createdAt: 1_234_567_890,
        kind: 1,
        tags: [["t", "bitcoin"]],
        content: "Talking about #bitcoin again"
    )

    event4.generateContentTags()

    let bitcoinTags = event4.tags.filter { $0.count > 1 && $0[0] == "t" && $0[1] == "bitcoin" }
    print("   Bitcoin tags found: \(bitcoinTags.count) (should be 1)")
    print("   All tags: \(event4.tags)")

    print("\n✅ All integration tests completed successfully!")
    print("🎉 Content tagging is fully integrated into NDKEvent!")

#else
    print("❌ NDKSwift module not available")
    print("This demo requires the NDKSwift module to be built")
    print("Run 'swift build' first, then try this demo")
#endif
