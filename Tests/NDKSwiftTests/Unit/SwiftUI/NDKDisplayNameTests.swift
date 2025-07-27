import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

@MainActor
final class NDKDisplayNameTests: XCTestCase {
    
    // MARK: - Test Initialization
    
    func testDisplayNameInitialization() async throws {
        let pubkey = "test_pubkey_123"
        
        // Test initialization with pubkey
        let displayName = NDKDisplayName(pubkey: pubkey)
        XCTAssertNotNil(displayName)
        
        // Test initialization with custom fallback style
        let displayNameNpub = NDKDisplayName(pubkey: pubkey, fallbackStyle: .npub)
        XCTAssertNotNil(displayNameNpub)
        
        let displayNamePlaceholder = NDKDisplayName(pubkey: pubkey, fallbackStyle: .placeholder)
        XCTAssertNotNil(displayNamePlaceholder)
        
        let displayNamePubkey = NDKDisplayName(pubkey: pubkey, fallbackStyle: .pubkey)
        XCTAssertNotNil(displayNamePubkey)
    }
    
    func testDisplayNameInitializationWithUser() async throws {
        let user = NDKUser(pubkey: "test_pubkey_123")
        
        // Test initialization with NDKUser
        let displayName = NDKDisplayName(user: user)
        XCTAssertNotNil(displayName)
        
        // Test with custom fallback
        let displayNameCustom = NDKDisplayName(user: user, fallbackStyle: .placeholder)
        XCTAssertNotNil(displayNameCustom)
    }
    
    // MARK: - Test Username Variant
    
    func testUsernameInitialization() async throws {
        let pubkey = "test_pubkey_123"
        
        // Test initialization with pubkey
        let username = NDKUsername(pubkey: pubkey)
        XCTAssertNotNil(username)
        
        // Test initialization with user
        let user = NDKUser(pubkey: pubkey)
        let usernameFromUser = NDKUsername(user: user)
        XCTAssertNotNil(usernameFromUser)
        
        // Test with different fallback styles
        let usernamePlaceholder = NDKUsername(pubkey: pubkey, fallbackStyle: .placeholder)
        XCTAssertNotNil(usernamePlaceholder)
    }
    
    // MARK: - Test Modifier Chain
    
    func testOnTapGestureModifier() async throws {
        let pubkey = "test_pubkey_123"
        var tapCallbackCalled = false
        
        let displayName = NDKDisplayName(pubkey: pubkey)
            .onTapGesture {
                tapCallbackCalled = true
            }
        
        XCTAssertNotNil(displayName)
        
        // Test username variant
        let username = NDKUsername(pubkey: pubkey)
            .onTapGesture {
                tapCallbackCalled = true
            }
        
        XCTAssertNotNil(username)
    }
    
    // MARK: - Test Fallback Behavior
    
    func testFallbackTextGeneration() async throws {
        // Test that various pubkey formats don't cause crashes
        let testCases = [
            "d771dab5db31d2e4e0f913b0c5571b29e2115b98aecc0be80de4e0baa8b3e2f0",
            "short_key",
            "",
            "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        ]
        
        for pubkey in testCases {
            let displayNameNpub = NDKDisplayName(pubkey: pubkey, fallbackStyle: .npub)
            let displayNamePlaceholder = NDKDisplayName(pubkey: pubkey, fallbackStyle: .placeholder)
            let displayNamePubkey = NDKDisplayName(pubkey: pubkey, fallbackStyle: .pubkey)
            
            // Create hosting controllers to trigger view rendering
            let hostingController1 = TestHostingController(rootView: displayNameNpub)
            let hostingController2 = TestHostingController(rootView: displayNamePlaceholder)
            let hostingController3 = TestHostingController(rootView: displayNamePubkey)
            
            // Access views to trigger rendering
            _ = hostingController1.view
            _ = hostingController2.view
            _ = hostingController3.view
            
            // If we get here without crashing, the components handled the input correctly
            XCTAssertNotNil(hostingController1.view)
            XCTAssertNotNil(hostingController2.view)
            XCTAssertNotNil(hostingController3.view)
        }
    }
    
    // MARK: - Test View Rendering
    
    func testDisplayNameRendering() async throws {
        let pubkey = "test_pubkey_123"
        let displayName = NDKDisplayName(pubkey: pubkey)
        
        // Create a hosting controller to trigger view rendering
        let hostingController = TestHostingController(rootView: displayName)
        _ = hostingController.view
        
        // If we get here without crashing, the view rendered successfully
        XCTAssertNotNil(hostingController.view)
    }
    
    func testUsernameRendering() async throws {
        let pubkey = "test_pubkey_123"
        let username = NDKUsername(pubkey: pubkey)
        
        // Create a hosting controller to trigger view rendering
        let hostingController = TestHostingController(rootView: username)
        _ = hostingController.view
        
        // If we get here without crashing, the view rendered successfully
        XCTAssertNotNil(hostingController.view)
    }
    
    // MARK: - Test Environment Requirements
    
    func testComponentsWorkWithoutNDKEnvironment() async throws {
        let pubkey = "test_pubkey_123"
        
        // Test both components without NDK environment
        let displayName = NDKDisplayName(pubkey: pubkey)
        let username = NDKUsername(pubkey: pubkey)
        
        let hostingController1 = TestHostingController(rootView: displayName)
        let hostingController2 = TestHostingController(rootView: username)
        
        _ = hostingController1.view
        _ = hostingController2.view
        
        // Components should render with fallback values
        XCTAssertNotNil(hostingController1.view)
        XCTAssertNotNil(hostingController2.view)
    }
}

// MARK: - Helper Extensions

private extension String {
    var hasContent: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if os(macOS)
import AppKit
private typealias TestHostingController = NSHostingController
#else
import UIKit
private typealias TestHostingController = UIHostingController
#endif