import XCTest
@testable import NDKSwift

final class NDKAuthErrorTests: XCTestCase {
    
    func testCorruptedSessionDataError() {
        // Test creating the error
        let sessionId = "test-session-123"
        let error = NDKAuthError.corruptedSessionData(sessionId: sessionId)
        
        // Test error description
        XCTAssertEqual(error.errorDescription, "Session data is corrupted for session: \(sessionId)")
        
        // Test pattern matching
        if case .corruptedSessionData(let id) = error {
            XCTAssertEqual(id, sessionId)
        } else {
            XCTFail("Pattern matching failed for corruptedSessionData")
        }
    }
    
    func testCorruptedSessionDataEquality() {
        let error1 = NDKAuthError.corruptedSessionData(sessionId: "session1")
        let error2 = NDKAuthError.corruptedSessionData(sessionId: "session1")
        let error3 = NDKAuthError.corruptedSessionData(sessionId: "session2")
        
        // Same session ID should be equal
        XCTAssertEqual(error1, error2)
        
        // Different session ID should not be equal
        XCTAssertNotEqual(error1, error3)
    }
    
    func testErrorCasting() {
        let error: Error = NDKAuthError.corruptedSessionData(sessionId: "test")
        
        // Test casting to NDKAuthError
        if let authError = error as? NDKAuthError,
           case .corruptedSessionData(let sessionId) = authError {
            XCTAssertEqual(sessionId, "test")
        } else {
            XCTFail("Failed to cast Error to NDKAuthError")
        }
    }
    
    func testDecodingErrorHandling() async {
        // This simulates what happens in restoreActiveSession
        let simulateRestoreSession: () async throws -> Void = {
            do {
                // Simulate a decoding error
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test decoding error"))
            } catch is DecodingError {
                // This is what restoreActiveSession does
                throw NDKAuthError.corruptedSessionData(sessionId: "test-session")
            }
        }
        
        do {
            try await simulateRestoreSession()
            XCTFail("Expected error to be thrown")
        } catch let error as NDKAuthError {
            if case .corruptedSessionData(let sessionId) = error {
                XCTAssertEqual(sessionId, "test-session")
            } else {
                XCTFail("Expected corruptedSessionData error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}