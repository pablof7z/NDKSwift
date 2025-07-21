import Foundation
import NDKSwift

// Standalone test to verify profile semantic caching

let testPubkey = "test_pubkey_123"

// Create and test profile
Task {
    do {
        print("Creating in-memory cache...")
        let cache = try await NDKSQLiteCache(path: ":memory:", debugMode: true)
        
        print("\n1. Testing profile save with semantic fields...")
        var profile = NDKUserProfile(
            name: "Alice",
            displayName: "Alice in Nostrland",
            about: "Testing semantic caching",
            picture: "https://example.com/alice.jpg",
            nip05: "alice@nostr.example"
        )
        
        // Add additional fields
        profile.setAdditionalField("pronouns", value: "she/her")
        profile.setAdditionalField("location", value: "Wonderland")
        
        // Save profile
        try await cache.saveProfile(profile, pubkey: testPubkey)
        print("✅ Profile saved")
        
        print("\n2. Testing profile retrieval (should use semantic fields, not JSON)...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Retrieve profile 100 times to test performance
        var retrievedProfile: NDKUserProfile?
        for i in 0..<100 {
            retrievedProfile = await cache.getProfile(pubkey: testPubkey)
            if i == 0 {
                print("✅ First retrieval successful")
            }
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = elapsed / 100.0 * 1000 // Convert to milliseconds
        
        print("\n3. Performance results:")
        print("   - Total time for 100 retrievals: \(String(format: "%.2f", elapsed))s")
        print("   - Average time per retrieval: \(String(format: "%.3f", averageTime))ms")
        
        if averageTime < 1.0 {
            print("   ✅ PASS: Retrieval is fast (<1ms average)")
        } else {
            print("   ❌ FAIL: Retrieval is slow (>1ms average)")
        }
        
        print("\n4. Verifying retrieved data...")
        if let profile = retrievedProfile {
            let allCorrect = 
                profile.name == "Alice" &&
                profile.displayName == "Alice in Nostrland" &&
                profile.about == "Testing semantic caching" &&
                profile.picture == "https://example.com/alice.jpg" &&
                profile.nip05 == "alice@nostr.example" &&
                profile.additionalField("pronouns") == "she/her" &&
                profile.additionalField("location") == "Wonderland"
            
            if allCorrect {
                print("   ✅ PASS: All fields retrieved correctly")
            } else {
                print("   ❌ FAIL: Some fields incorrect")
                print("   - name: \(profile.name ?? "nil")")
                print("   - displayName: \(profile.displayName ?? "nil")")
                print("   - pronouns: \(profile.additionalField("pronouns") ?? "nil")")
            }
        } else {
            print("   ❌ FAIL: Profile not retrieved")
        }
        
        print("\n5. Testing backward compatibility with JSON-only profiles...")
        
        // Insert a legacy profile (JSON only)
        let legacyPubkey = "legacy_pubkey"
        let jsonProfile = """
        {
            "name": "Legacy User",
            "display_name": "Legacy Display",
            "about": "A user from before semantic caching",
            "custom_field": "custom_value"
        }
        """
        
        try await cache.insertRawProfileForTesting(pubkey: legacyPubkey, json: jsonProfile)
        
        // Retrieve legacy profile
        let legacyProfile = await cache.getProfile(pubkey: legacyPubkey)
        
        if let profile = legacyProfile,
           profile.name == "Legacy User",
           profile.displayName == "Legacy Display",
           profile.additionalField("custom_field") == "custom_value" {
            print("   ✅ PASS: Legacy JSON profiles still work")
        } else {
            print("   ❌ FAIL: Legacy JSON profile retrieval failed")
        }
        
        print("\n✅ Profile semantic caching test completed successfully!")
        
    } catch {
        print("\n❌ Test failed with error: \(error)")
    }
}

// Keep process alive
RunLoop.current.run()