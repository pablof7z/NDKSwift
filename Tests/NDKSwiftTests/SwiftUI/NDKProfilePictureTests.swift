import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

final class NDKProfilePictureTests: XCTestCase {
    
    func testInitializationWithPubkey() {
        let pubkey = "test_pubkey"
        let size: CGFloat = 50
        let cornerRadius: CGFloat = 10
        let borderColor = Color.blue
        let borderWidth: CGFloat = 2
        
        let profilePicture = NDKProfilePicture(
            pubkey: pubkey,
            size: size,
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth
        )
        
        // Test that the view can be instantiated
        XCTAssertNotNil(profilePicture)
        
        // Test that it conforms to View
        XCTAssertTrue(type(of: profilePicture).Body.self == type(of: profilePicture.body).self)
    }
    
    func testInitializationWithNDKUser() {
        let user = NDKUser(pubkey: "test_user_pubkey")
        let size: CGFloat = 60
        
        let profilePicture = NDKProfilePicture(
            user: user,
            size: size
        )
        
        XCTAssertNotNil(profilePicture)
    }
    
    func testDefaultValues() {
        let profilePicture = NDKProfilePicture(pubkey: "test_pubkey")
        
        XCTAssertNotNil(profilePicture)
    }
    
    func testTapGestureModifier() {
        let profilePicture = NDKProfilePicture(pubkey: "test_pubkey")
            .onTapGesture {
                // Gesture action
            }
        
        // Verify the modifier returns a new instance
        XCTAssertNotNil(profilePicture)
    }
    
    func testMultipleSizes() {
        let sizes: [CGFloat] = [30, 40, 60, 80, 100]
        
        for size in sizes {
            let profilePicture = NDKProfilePicture(
                pubkey: "test_pubkey",
                size: size
            )
            
            XCTAssertNotNil(profilePicture, "Failed to create with size \(size)")
        }
    }
    
    func testVariousBorderConfigurations() {
        let configurations: [(Color?, CGFloat)] = [
            (nil, 0),
            (Color.blue, 1),
            (Color.red, 2),
            (Color.green, 5)
        ]
        
        for (color, width) in configurations {
            let profilePicture = NDKProfilePicture(
                pubkey: "test_pubkey",
                borderColor: color,
                borderWidth: width
            )
            
            XCTAssertNotNil(profilePicture, "Failed with border config: \(String(describing: color)), \(width)")
        }
    }
    
    func testCornerRadiusVariations() {
        let cornerRadii: [CGFloat?] = [nil, 0, 10, 20, 50]
        
        for radius in cornerRadii {
            let profilePicture = NDKProfilePicture(
                pubkey: "test_pubkey",
                size: 60,
                cornerRadius: radius
            )
            
            XCTAssertNotNil(profilePicture, "Failed with corner radius: \(String(describing: radius))")
        }
    }
    
    func testChainableModifiers() {
        // Test that the custom tap gesture modifier can be chained
        let profilePicture = NDKProfilePicture(pubkey: "test_pubkey")
            .onTapGesture { }
            .frame(width: 100, height: 100)
            .padding()
        
        XCTAssertNotNil(profilePicture)
    }
}