import Foundation
import NDKSwiftCore

/// A public, type-safe representation of mint information for caching
/// This mirrors CashuSwift.Mint.Info but with public properties
public struct NDKMintInfo: Codable, Equatable, Sendable {
    public let name: String?
    public let pubkey: String?
    public let version: String?
    public let description: String?
    public let descriptionLong: String?
    public let contact: [Contact]?
    public let motd: String?
    public let iconURL: String?
    public let urls: [String]?
    public let time: Int?
    public let tosURL: String?
    public let nuts: Nuts?

    public struct Contact: Codable, Equatable, Sendable {
        public let method: String
        public let info: String

        public init(method: String, info: String) {
            self.method = method
            self.info = info
        }
    }

    public struct Nuts: Codable, Equatable, Sendable {
        public let nut04: PaymentMethodList?
        public let nut05: PaymentMethodList?
        public let nut07: NutSupportFlag?
        public let nut08: NutSupportFlag?
        public let nut09: NutSupportFlag?
        public let nut10: NutSupportFlag?
        public let nut12: NutSupportFlag?

        enum CodingKeys: String, CodingKey {
            case nut04 = "4"
            case nut05 = "5"
            case nut07 = "7"
            case nut08 = "8"
            case nut09 = "9"
            case nut10 = "10"
            case nut12 = "12"
        }

        public init(
            nut04: PaymentMethodList? = nil,
            nut05: PaymentMethodList? = nil,
            nut07: NutSupportFlag? = nil,
            nut08: NutSupportFlag? = nil,
            nut09: NutSupportFlag? = nil,
            nut10: NutSupportFlag? = nil,
            nut12: NutSupportFlag? = nil
        ) {
            self.nut04 = nut04
            self.nut05 = nut05
            self.nut07 = nut07
            self.nut08 = nut08
            self.nut09 = nut09
            self.nut10 = nut10
            self.nut12 = nut12
        }
    }

    public struct PaymentMethodList: Codable, Equatable, Sendable {
        public let methods: [PaymentMethod]?
        public let disabled: Bool?

        public init(methods: [PaymentMethod]?, disabled: Bool?) {
            self.methods = methods
            self.disabled = disabled
        }
    }

    public struct PaymentMethod: Codable, Equatable, Sendable {
        public let method: String
        public let unit: String
        public let minAmount: Int?
        public let maxAmount: Int?

        enum CodingKeys: String, CodingKey {
            case method, unit
            case minAmount = "min_amount"
            case maxAmount = "max_amount"
        }

        public init(method: String, unit: String, minAmount: Int? = nil, maxAmount: Int? = nil) {
            self.method = method
            self.unit = unit
            self.minAmount = minAmount
            self.maxAmount = maxAmount
        }
    }

    public struct NutSupportFlag: Codable, Equatable, Sendable {
        public let supported: Bool

        public init(supported: Bool) {
            self.supported = supported
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, pubkey, version, description, contact, motd, urls, time, nuts
        case descriptionLong = "description_long"
        case iconURL = "icon_url"
        case tosURL = "tos_url"
    }

    public init(
        name: String? = nil,
        pubkey: String? = nil,
        version: String? = nil,
        description: String? = nil,
        descriptionLong: String? = nil,
        contact: [Contact]? = nil,
        motd: String? = nil,
        iconURL: String? = nil,
        urls: [String]? = nil,
        time: Int? = nil,
        tosURL: String? = nil,
        nuts: Nuts? = nil
    ) {
        self.name = name
        self.pubkey = pubkey
        self.version = version
        self.description = description
        self.descriptionLong = descriptionLong
        self.contact = contact
        self.motd = motd
        self.iconURL = iconURL
        self.urls = urls
        self.time = time
        self.tosURL = tosURL
        self.nuts = nuts
    }

    /// Initialize from JSON data
    public init(from jsonData: Data) throws {
        self = try JSONCoding.decode(NDKMintInfo.self, from: jsonData)
    }

    /// Convert to JSON data
    public func toJSONData() throws -> Data {
        return try JSONCoding.encode(self)
    }
}
