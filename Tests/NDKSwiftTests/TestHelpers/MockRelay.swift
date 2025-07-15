import Foundation
@testable import NDKSwift

/// Mock implementation of relay for testing
class MockRelay {
    let url: String
    var shouldFailPublish = false
    var publishDelay: TimeInterval?
    var publishedEvents: [NDKEvent] = []
    var publishResults: [String: Bool] = [:]
    var isConnected: Bool = true
    
    init(url: String) {
        self.url = url
    }
    
    /// Set specific result for an event ID
    func setPublishResult(for eventId: String, success: Bool) {
        publishResults[eventId] = success
    }
    
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        // Store the published event
        publishedEvents.append(event)
        
        // Simulate delay if configured
        if let delay = publishDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Check for specific result
        if let specificResult = publishResults[event.id] {
            if specificResult {
                return (success: true, message: nil)
            } else {
                return (success: false, message: "Mock: Event rejected")
            }
        }
        
        // Use general failure flag
        if shouldFailPublish {
            throw NDKError.relayError(relay: url, message: "Mock relay publish failure")
        }
        
        return (success: true, message: nil)
    }
    
    func reset() {
        publishedEvents.removeAll()
        publishResults.removeAll()
        shouldFailPublish = false
        publishDelay = nil
        isConnected = true
    }
}