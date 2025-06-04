#!/usr/bin/env swift

import Foundation
import NDKSwift

@main
struct TestAccountCreation {
    static func main() async {
        print("Testing NDK account creation...")
        
        do {
            // Test 1: Generate a private key signer
            print("1. Generating private key signer...")
            let signer = try NDKPrivateKeySigner.generate()
            print("✅ Signer generated successfully")
            
            // Test 2: Get keys
            print("2. Getting keys...")
            let nsec = try signer.nsec
            let npub = try signer.npub  
            let pubkey = try await signer.pubkey
            
            print("✅ Keys generated:")
            print("   nsec: \(nsec.prefix(20))...")
            print("   npub: \(npub.prefix(20))...")
            print("   pubkey: \(pubkey.prefix(20))...")
            
            // Test 3: Test nsec parsing
            print("3. Testing nsec parsing...")
            let signer2 = try NDKPrivateKeySigner(nsec: nsec)
            let npub2 = try signer2.npub
            print("✅ Nsec parsing works: \(npub2.prefix(20))...")
            
            print("🎉 All tests passed! NDK account creation works fine.")
            
        } catch {
            print("❌ Error: \(error)")
            print("   Error type: \(type(of: error))")
            if let ndkError = error as? NDKError {
                print("   NDK Error: \(ndkError)")
            }
        }
    }
}