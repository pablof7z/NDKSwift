import Foundation

/// NDKImage represents a Nostr image event (kind 20)
public struct NDKImage {
    
    // MARK: - Static Properties
    
    /// The primary kind for image events
    public static let kind: Kind = EventKind.image
    
    /// All supported kinds for this event type
    public static let kinds: [Kind] = [EventKind.image]
    
    // MARK: - Properties
    
    /// The underlying event
    public let event: NDKEvent
    
    /// Cached imeta tags for performance
    private var _imetas: [NDKImetaTag]?
    
    // MARK: - Event Property Forwarding
    
    /// The event ID
    public var id: EventID? {
        get { event.id }
        set { event.id = newValue }
    }
    
    /// The public key of the event creator
    public var pubkey: PublicKey {
        get { event.pubkey }
        set { event.pubkey = newValue }
    }
    
    /// The timestamp when the event was created
    public var createdAt: Timestamp {
        get { event.createdAt }
        set { event.createdAt = newValue }
    }
    
    /// The event kind (always EventKind.image for NDKImage)
    public var kind: Kind {
        get { event.kind }
        set { event.kind = newValue }
    }
    
    /// The event content
    public var content: String {
        get { event.content }
        set { event.content = newValue }
    }
    
    /// The event tags
    public var tags: [[String]] {
        get { event.tags }
        set { event.tags = newValue }
    }
    
    /// The event signature
    public var sig: String? {
        get { event.sig }
        set { event.sig = newValue }
    }
    
    /// The associated NDK instance
    public var ndk: NDK? {
        get { event.ndk }
        set { event.ndk = newValue }
    }
    
    // MARK: - Initialization
    
    /// Initialize a new NDKImage event
    public init(ndk: NDK? = nil, pubkey: PublicKey = "") {
        self.event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: NDKImage.kind,
            tags: [],
            content: ""
        )
        self.event.ndk = ndk
    }
    
    /// Create an NDKImage from an existing NDKEvent
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create an NDKImage from an existing NDKEvent
    public static func from(event: NDKEvent) -> NDKImage {
        return NDKImage(event: event)
    }
    
    // MARK: - Validation
    
    /// Check if this image event is valid (has at least one imeta tag with a URL)
    public var isValid: Bool {
        return !imetas.isEmpty && imetas.contains { $0.url != nil }
    }
    
    // MARK: - Imeta Tag Management
    
    /// Get all imeta tags from this image event
    public var imetas: [NDKImetaTag] {
        let imetaTags = event.tags
            .filter { $0.first == "imeta" }
            .compactMap { ImetaUtils.mapImetaTag($0) }
            .filter { $0.url != nil }
        
        return imetaTags
    }
    
    /// Set imeta tags for this image event
    public mutating func setImetas(_ newImetas: [NDKImetaTag]) {
        // Remove all existing imeta tags
        event.tags = event.tags.filter { $0.first != "imeta" }
        
        // Add new imeta tags
        for imeta in newImetas {
            let tag = ImetaUtils.imetaTagToTag(imeta)
            event.tags.append(tag)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Add a single imeta tag
    public mutating func addImeta(_ imeta: NDKImetaTag) {
        let tag = ImetaUtils.imetaTagToTag(imeta)
        event.tags.append(tag)
    }
    
    /// Get the primary image URL (from the first imeta tag)
    public var primaryImageURL: String? {
        return imetas.first?.url
    }
    
    /// Get all image URLs
    public var imageURLs: [String] {
        return imetas.compactMap { $0.url }
    }
    
    /// Get dimensions for the primary image
    public var primaryImageDimensions: (width: Int, height: Int)? {
        guard let dim = imetas.first?.dim else { return nil }
        let parts = dim.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else { return nil }
        return (width, height)
    }
    
    // MARK: - Convenience Tag Methods
    
    /// Add a tag to the image
    public mutating func addTag(_ tag: [String]) {
        event.addTag(tag)
    }
    
    /// Get tags matching a specific tag name
    public func tags(withName tagName: String) -> [[String]] {
        return event.tags(withName: tagName)
    }
    
    /// Get the first value of a tag with the given name
    public func tagValue(_ tagName: String) -> String? {
        return event.tagValue(tagName)
    }
}