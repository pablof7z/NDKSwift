import Foundation

// MARK: - Test Types

/// Simple user profile structure for tests
/// This is a test-only type used to simulate user profile data
struct NDKUserProfile: Codable {
    var name: String?
    var displayName: String?
    var about: String?
    var picture: String?
    var banner: String?
    var nip05: String?
    var lud16: String?
    var lud06: String?
    var website: String?
    
    // Additional fields that can be stored
    var additionalFields: [String: String] = [:]
    
    mutating func setAdditionalField(_ key: String, value: String) {
        additionalFields[key] = value
    }
    
    func additionalField(_ key: String) -> String? {
        return additionalFields[key]
    }
    
    init(
        name: String? = nil,
        displayName: String? = nil,
        about: String? = nil,
        picture: String? = nil,
        banner: String? = nil,
        nip05: String? = nil,
        lud16: String? = nil,
        lud06: String? = nil,
        website: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.about = about
        self.picture = picture
        self.banner = banner
        self.nip05 = nip05
        self.lud16 = lud16
        self.lud06 = lud06
        self.website = website
    }
    
    // Custom coding to handle additional fields
    enum CodingKeys: String, CodingKey {
        case name, displayName = "display_name", about, picture, banner, nip05, lud16, lud06, website
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        about = try container.decodeIfPresent(String.self, forKey: .about)
        picture = try container.decodeIfPresent(String.self, forKey: .picture)
        banner = try container.decodeIfPresent(String.self, forKey: .banner)
        nip05 = try container.decodeIfPresent(String.self, forKey: .nip05)
        lud16 = try container.decodeIfPresent(String.self, forKey: .lud16)
        lud06 = try container.decodeIfPresent(String.self, forKey: .lud06)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        
        // Decode any additional fields
        if let dynamicContainer = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            for key in dynamicContainer.allKeys {
                if !CodingKeys.allCases.contains(where: { $0.stringValue == key.stringValue }) {
                    if let value = try? dynamicContainer.decode(String.self, forKey: key) {
                        additionalFields[key.stringValue] = value
                    }
                }
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(about, forKey: .about)
        try container.encodeIfPresent(picture, forKey: .picture)
        try container.encodeIfPresent(banner, forKey: .banner)
        try container.encodeIfPresent(nip05, forKey: .nip05)
        try container.encodeIfPresent(lud16, forKey: .lud16)
        try container.encodeIfPresent(lud06, forKey: .lud06)
        try container.encodeIfPresent(website, forKey: .website)
        
        // Encode additional fields
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in additionalFields {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            try dynamicContainer.encode(value, forKey: codingKey)
        }
    }
}

// Helper for dynamic coding keys
private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        return nil
    }
}

// Make CodingKeys conform to CaseIterable for the check
extension NDKUserProfile.CodingKeys: CaseIterable {
    static var allCases: [NDKUserProfile.CodingKeys] {
        return [.name, .displayName, .about, .picture, .banner, .nip05, .lud16, .lud06, .website]
    }
}