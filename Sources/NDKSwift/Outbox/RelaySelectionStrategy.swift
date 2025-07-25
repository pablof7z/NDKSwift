import Foundation

/// Custom relay selection strategy that can be provided by users
public struct RelaySelectionStrategy {
    /// Closure that selects relays for a given public key
    public let selectRelays: (String) async -> [String]

    public init(selectRelays: @escaping (String) async -> [String]) {
        self.selectRelays = selectRelays
    }
}