import Foundation

/// NIP-60 Mint Announcement event (kind 38000)
public struct NDKMintAnnouncement: Codable, Sendable {
    public let mintURL: URL
    public let name: String?
    public let description: String?
    public let descriptions: [String: String]?
    public let pubkey: String?
    public let contact: [[String]]?
    public let motd: String?
    public let units: [String]?
    public let nuts: [String: Any]?
    public let icon: URL?
    
    enum CodingKeys: String, CodingKey {
        case mintURL = "mint_url"
        case name
        case description
        case descriptions
        case pubkey
        case contact
        case motd
        case units
        case nuts
        case icon
    }
    
    public init(mintURL: URL, name: String? = nil, description: String? = nil,
                descriptions: [String: String]? = nil, pubkey: String? = nil,
                contact: [[String]]? = nil, motd: String? = nil,
                units: [String]? = nil, nuts: [String: Any]? = nil,
                icon: URL? = nil) {
        self.mintURL = mintURL
        self.name = name
        self.description = description
        self.descriptions = descriptions
        self.pubkey = pubkey
        self.contact = contact
        self.motd = motd
        self.units = units
        self.nuts = nuts
        self.icon = icon
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let mintURLString = try container.decode(String.self, forKey: .mintURL)
        guard let url = URL(string: mintURLString) else {
            throw DecodingError.dataCorruptedError(forKey: .mintURL,
                                                    in: container,
                                                    debugDescription: "Invalid mint URL")
        }
        self.mintURL = url
        
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.descriptions = try container.decodeIfPresent([String: String].self, forKey: .descriptions)
        self.pubkey = try container.decodeIfPresent(String.self, forKey: .pubkey)
        self.contact = try container.decodeIfPresent([[String]].self, forKey: .contact)
        self.motd = try container.decodeIfPresent(String.self, forKey: .motd)
        self.units = try container.decodeIfPresent([String].self, forKey: .units)
        
        // Handle nuts as dynamic JSON
        if let nutsData = try? container.decodeIfPresent(Data.self, forKey: .nuts),
           let nutsJSON = try? JSONSerialization.jsonObject(with: nutsData) as? [String: Any] {
            self.nuts = nutsJSON
        } else {
            self.nuts = nil
        }
        
        if let iconString = try container.decodeIfPresent(String.self, forKey: .icon) {
            self.icon = URL(string: iconString)
        } else {
            self.icon = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(mintURL.absoluteString, forKey: .mintURL)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(descriptions, forKey: .descriptions)
        try container.encodeIfPresent(pubkey, forKey: .pubkey)
        try container.encodeIfPresent(contact, forKey: .contact)
        try container.encodeIfPresent(motd, forKey: .motd)
        try container.encodeIfPresent(units, forKey: .units)
        
        if let nuts = nuts {
            let nutsData = try JSONSerialization.data(withJSONObject: nuts)
            try container.encode(nutsData, forKey: .nuts)
        }
        
        try container.encodeIfPresent(icon?.absoluteString, forKey: .icon)
    }
}

// MARK: - NDKEvent Extension
extension NDKEvent {
    /// Creates a mint announcement event (kind 38000)
    public static func mintAnnouncement(announcement: NDKMintAnnouncement, keypair: NDKKeypair) throws -> NDKEvent {
        let content = try JSONEncoder().encode(announcement)
        let contentString = String(data: content, encoding: .utf8) ?? "{}"
        
        var event = NDKEvent(kind: .mintAnnouncement, content: contentString, keypair: keypair)
        
        // Add tags for mint URL and units for easier filtering
        event.tags.append(["u", announcement.mintURL.absoluteString])
        
        if let units = announcement.units {
            for unit in units {
                event.tags.append(["unit", unit])
            }
        }
        
        return event
    }
    
    /// Parses a mint announcement from the event content
    public func parseMintAnnouncement() throws -> NDKMintAnnouncement? {
        guard kind == .mintAnnouncement else { return nil }
        
        let data = content.data(using: .utf8) ?? Data()
        return try JSONDecoder().decode(NDKMintAnnouncement.self, from: data)
    }
}