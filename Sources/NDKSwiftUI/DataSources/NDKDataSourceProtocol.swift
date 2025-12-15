import Combine
import Foundation

/// Base protocol for NDKSwiftUI data sources
public protocol NDKSubscriptionProtocol: ObservableObject {
    /// The current error state of the data source
    var error: Error? { get }

    /// Whether the data source is currently loading
    var isLoading: Bool { get }
}

/// Extension providing common functionality for data sources
public extension NDKSubscriptionProtocol {
    /// Clears the error state
    func clearError() {
        // Default implementation - subclasses can override
    }
}
