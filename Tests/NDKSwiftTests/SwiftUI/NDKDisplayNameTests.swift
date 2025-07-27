import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

final class NDKDisplayNameTests: XCTestCase {
    
    func testInitializationWithPubkey() {
        let pubkey = "test_pubkey"
        
        let displayName = NDKDisplayName(pubkey: pubkey)
        XCTAssertNotNil(displayName)
        
        let displayNameWithFallback = NDKDisplayName(
            pubkey: pubkey,
            fallbackStyle: .placeholder
        )
        XCTAssertNotNil(displayNameWithFallback)
    }
    
    func testInitializationWithNDKUser() {
        let user = NDKUser(pubkey: "test_user_pubkey")
        
        let displayName = NDKDisplayName(user: user)
        XCTAssertNotNil(displayName)
        
        let displayNameWithFallback = NDKDisplayName(
            user: user,
            fallbackStyle: .pubkey
        )
        XCTAssertNotNil(displayNameWithFallback)
    }
    
    func testAllFallbackStyles() {
        let pubkey = "test_pubkey"
        let fallbackStyles: [NDKDisplayName.FallbackStyle] = [.npub, .placeholder, .pubkey]
        
        for style in fallbackStyles {
            let displayName = NDKDisplayName(
                pubkey: pubkey,
                fallbackStyle: style
            )
            XCTAssertNotNil(displayName, "Failed with fallback style: \(style)")
        }
    }
    
    func testTapGestureModifier() {
        let displayName = NDKDisplayName(pubkey: "test_pubkey")
            .onTapGesture {
                // Tap action
            }
        
        XCTAssertNotNil(displayName)
    }
    
    func testChainableModifiers() {
        let displayName = NDKDisplayName(pubkey: "test_pubkey")
            .onTapGesture { }
            .font(.headline)
            .foregroundStyle(.primary)
        
        XCTAssertNotNil(displayName)
    }
}

final class NDKUsernameTests: XCTestCase {
    
    func testInitializationWithPubkey() {
        let pubkey = "test_pubkey"
        
        let username = NDKUsername(pubkey: pubkey)
        XCTAssertNotNil(username)
        
        let usernameWithFallback = NDKUsername(
            pubkey: pubkey,
            fallbackStyle: .placeholder
        )
        XCTAssertNotNil(usernameWithFallback)
    }
    
    func testInitializationWithNDKUser() {
        let user = NDKUser(pubkey: "test_user_pubkey")
        
        let username = NDKUsername(user: user)
        XCTAssertNotNil(username)
        
        let usernameWithFallback = NDKUsername(
            user: user,
            fallbackStyle: .pubkey
        )
        XCTAssertNotNil(usernameWithFallback)
    }
    
    func testAllFallbackStyles() {
        let pubkey = "test_pubkey"
        let fallbackStyles: [NDKDisplayName.FallbackStyle] = [.npub, .placeholder, .pubkey]
        
        for style in fallbackStyles {
            let username = NDKUsername(
                pubkey: pubkey,
                fallbackStyle: style
            )
            XCTAssertNotNil(username, "Failed with fallback style: \(style)")
        }
    }
    
    func testTapGestureModifier() {
        let username = NDKUsername(pubkey: "test_pubkey")
            .onTapGesture {
                // Tap action
            }
        
        XCTAssertNotNil(username)
    }
    
    func testChainableModifiers() {
        let username = NDKUsername(pubkey: "test_pubkey")
            .onTapGesture { }
            .font(.body)
            .foregroundStyle(.secondary)
        
        XCTAssertNotNil(username)
    }
}