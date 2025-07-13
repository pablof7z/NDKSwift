import Foundation
@testable import NDKSwift

/// Mock relay for testing
class MockRelay {
    let url: URL
    var publishedEvents: [NDKEvent] = []
    var subscriptions: [String: NDKFilter] = [:]
    
    init(url: URL) {
        self.url = url
    }
    
    func publish(_ event: NDKEvent) {
        publishedEvents.append(event)
    }
    
    func subscribe(with filter: NDKFilter, id: String) {
        subscriptions[id] = filter
    }
    
    func unsubscribe(id: String) {
        subscriptions.removeValue(forKey: id)
    }
}