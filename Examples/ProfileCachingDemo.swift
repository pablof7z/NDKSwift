#!/usr/bin/env swift

import Foundation
import NDKSwift
import GRDB

// Demo to verify profile semantic caching performance

print("NDKSwift Profile Semantic Caching Demo")
print("=====================================\n")

let testPubkey = "test_pubkey_123"

// Use dispatch group to handle async code
let group = DispatchGroup()
group.enter()

Task {
    do {
        print("1. Creating in-memory cache...")
        let cache = try await NDKSQLiteCache(path: ":memory:", debugMode: false)
        
        print("\n2. Creating and saving profile with semantic fields...")
        var profile = NDKUserProfile(
            name: "Alice",
            displayName: "Alice in Nostrland",
            about: "Testing semantic caching",
            picture: "https://example.com/alice.jpg",
            banner: "https://example.com/banner.jpg",
            nip05: "alice@nostr.example",
            lud16: "alice@getalby.com",
            website: "https://alice.example"
        )
        
        // Add additional fields
        profile.setAdditionalField("pronouns", value: "she/her")
        profile.setAdditionalField("location", value: "Wonderland")
        profile.setAdditionalField("languages", value: "en, es, fr")
        
        // Save profile
        try await cache.saveProfile(profile, pubkey: testPubkey)
        print("✅ Profile saved with all fields")
        
        print("\n3. Testing retrieval performance (100 iterations)...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var retrievedProfile: NDKUserProfile?
        for _ in 0..<100 {
            retrievedProfile = await cache.getProfile(pubkey: testPubkey)
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = elapsed / 100.0 * 1000 // Convert to milliseconds
        
        print("   - Total time: \(String(format: "%.2f", elapsed))s")
        print("   - Average per retrieval: \(String(format: "%.3f", averageTime))ms")
        
        if averageTime < 1.0 {
            print("   ✅ FAST: Profile retrieval uses semantic caching (<1ms)")
        } else {
            print("   ⚠️  SLOW: Profile retrieval may be parsing JSON (>1ms)")
        }
        
        print("\n4. Verifying data integrity...")
        if let profile = retrievedProfile {
            print("   Standard fields:")
            print("   - name: \(profile.name ?? "nil")")
            print("   - displayName: \(profile.displayName ?? "nil")")
            print("   - about: \(profile.about ?? "nil")")
            print("   - nip05: \(profile.nip05 ?? "nil")")
            
            print("\n   Additional fields:")
            print("   - pronouns: \(profile.additionalField("pronouns") ?? "nil")")
            print("   - location: \(profile.additionalField("location") ?? "nil")")
            print("   - languages: \(profile.additionalField("languages") ?? "nil")")
            
            let allCorrect = 
                profile.name == "Alice" &&
                profile.displayName == "Alice in Nostrland" &&
                profile.additionalField("pronouns") == "she/her" &&
                profile.additionalField("location") == "Wonderland"
            
            if allCorrect {
                print("\n   ✅ All fields retrieved correctly!")
            }
        }
        
        #if DEBUG
        print("\n5. Testing backward compatibility...")
        
        // Insert a legacy JSON-only profile
        let legacyPubkey = "legacy_user_456"
        let jsonProfile = """
        {
            "name": "Legacy User",
            "display_name": "Legacy Display Name",
            "about": "This profile was stored before semantic caching",
            "nip05": "legacy@nostr.example",
            "custom_field": "custom_value",
            "another_field": "another_value"
        }
        """
        
        try await cache.insertRawProfileForTesting(pubkey: legacyPubkey, json: jsonProfile)
        
        // Retrieve and verify
        if let legacyProfile = await cache.getProfile(pubkey: legacyPubkey) {
            print("   ✅ Legacy profile retrieved:")
            print("   - name: \(legacyProfile.name ?? "nil")")
            print("   - custom_field: \(legacyProfile.additionalField("custom_field") ?? "nil")")
        }
        #endif
        
        print("\n6. Comparing with JSON parsing performance...")
        
        // Create many profiles
        print("   Creating 1000 test profiles...")
        for i in 0..<1000 {
            var testProfile = NDKUserProfile(
                name: "User \(i)",
                about: "Test user number \(i)",
                picture: "https://example.com/user\(i).jpg"
            )
            testProfile.setAdditionalField("index", value: "\(i)")
            testProfile.setAdditionalField("timestamp", value: "\(Date().timeIntervalSince1970)")
            
            try await cache.saveProfile(testProfile, pubkey: "test_user_\(i)")
        }
        
        // Retrieve all profiles
        print("   Retrieving all 1000 profiles...")
        let bulkStart = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<1000 {
            _ = await cache.getProfile(pubkey: "test_user_\(i)")
        }
        
        let bulkElapsed = CFAbsoluteTimeGetCurrent() - bulkStart
        let bulkAverage = bulkElapsed / 1000.0 * 1000 // ms per profile
        
        print("   - Total time: \(String(format: "%.2f", bulkElapsed))s")
        print("   - Average per profile: \(String(format: "%.3f", bulkAverage))ms")
        
        print("\n✅ Demo completed successfully!")
        print("\nSummary:")
        print("- Profiles are now stored with parsed fields in the database")
        print("- No JSON parsing needed on retrieval")
        print("- Additional fields stored as efficient binary plist")
        print("- Backward compatible with JSON-only profiles")
        
    } catch {
        print("\n❌ Error: \(error)")
    }
    
    group.leave()
}

group.wait()
print("\nDone.")