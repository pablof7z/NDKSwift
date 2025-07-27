import Foundation
import Combine

/// Base protocol for NDKSwiftUI data sources
public protocol NDKDataSourceProtocol: ObservableObject {
    /// The current error state of the data source
    var error: Error? { get }
    
    /// Whether the data source is currently loading
    var isLoading: Bool { get }
}

/// Extension providing common functionality for data sources
public extension NDKDataSourceProtocol {
    /// Clears the error state
    func clearError() {
        // Default implementation - subclasses can override
    }
}