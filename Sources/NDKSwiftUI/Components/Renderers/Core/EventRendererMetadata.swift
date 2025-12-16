import Foundation

/// Metadata protocol for event renderers to declare their capabilities and characteristics
public protocol EventRendererMetadata {
    /// Event kinds this renderer supports (e.g., [30023] for articles, [1] for notes)
    static var supportedKinds: [Int] { get }

    /// Semantic variant name (compact, hero, portrait, inline, etc.)
    static var variant: String { get }

    /// Category (article, note, highlight, user, etc.)
    static var category: String { get }

    /// Display priority (higher = preferred). Default is 1.
    /// Use this for progressive enhancement where higher priority renderers override lower ones.
    /// Priority scale:
    /// - 1: Basic/minimal features
    /// - 5: Standard/compact features
    /// - 10: Full/enhanced features
    static var priority: Int { get }
}

// MARK: - Default Implementations

public extension EventRendererMetadata {
    /// Default priority for renderers
    static var priority: Int { 1 }
}
