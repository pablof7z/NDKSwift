import Foundation

public struct RelayMetadata: Codable {
    public let name: String?
    public let description: String?
    public let pubkey: String?
    public let contact: String?
    public let supportedNips: [Int]?
    public let software: String?
    public let version: String?
    public let icon: String?

    enum CodingKeys: String, CodingKey {
        case name, description, pubkey, contact, software, version, icon
        case supportedNips = "supported_nips"
    }

    public var displayName: String {
        name ?? "Unknown Relay"
    }
}

@MainActor
public final class RelayMetadataCache: ObservableObject {
    public static let shared = RelayMetadataCache()

    @Published public private(set) var metadata: [String: RelayMetadata] = [:]
    @Published public private(set) var loading: Set<String> = []

    private init() {}

    public func fetchMetadata(for relayURL: String) async {
        guard metadata[relayURL] == nil, !loading.contains(relayURL) else { return }

        loading.insert(relayURL)

        guard let httpURL = relayURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://") as String?,
              let url = URL(string: httpURL) else {
            loading.remove(relayURL)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let relayMetadata = try JSONDecoder().decode(RelayMetadata.self, from: data)
            metadata[relayURL] = relayMetadata
        } catch {
            // Use hostname as fallback
            let fallbackName = url.host ?? relayURL
            metadata[relayURL] = RelayMetadata(
                name: fallbackName,
                description: nil,
                pubkey: nil,
                contact: nil,
                supportedNips: nil,
                software: nil,
                version: nil,
                icon: nil
            )
        }

        loading.remove(relayURL)
    }

    public func displayName(for relayURL: String) -> String {
        if let meta = metadata[relayURL] {
            return meta.displayName
        }
        // Fallback to hostname while loading
        return URL(string: relayURL.replacingOccurrences(of: "wss://", with: "https://"))?.host ?? relayURL
    }
}
