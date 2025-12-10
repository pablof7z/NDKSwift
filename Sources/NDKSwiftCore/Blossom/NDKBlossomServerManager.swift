import Foundation
import Observation

/// Standard Blossom server information for discovery (kind 36363)
public struct NDKBlossomServerInfo: Identifiable, Equatable, Hashable {
    public let id: String
    public let url: String
    public let name: String
    public let description: String
    public let isPaid: Bool
    public let isWhitelisted: Bool
    public let whitelistMessage: String?
    public let paidMessage: String?
    
    public init(url: String, name: String, description: String = "", isPaid: Bool = false, isWhitelisted: Bool = false, whitelistMessage: String? = nil, paidMessage: String? = nil) {
        self.id = url
        self.url = url
        self.name = name
        self.description = description
        self.isPaid = isPaid
        self.isWhitelisted = isWhitelisted
        self.whitelistMessage = whitelistMessage
        self.paidMessage = paidMessage
    }
    
    public init(from event: NDKEvent) {
        self.id = event.id
        self.description = event.content
        
        var extractedUrl = ""
        var extractedName = ""
        var extractedIsPaid = false
        var extractedIsWhitelisted = false
        var extractedWhitelistMessage: String?
        var extractedPaidMessage: String?
        
        // Parse tags
        for tag in event.tags {
            guard tag.count >= 2 else { continue }
            
            switch tag[0] {
            case "d":
                extractedUrl = tag[1]
            case "name":
                extractedName = tag[1]
            case "paid":
                extractedIsPaid = true
                if tag.count > 1 {
                    extractedPaidMessage = tag[1]
                }
            case "whitelist":
                extractedIsWhitelisted = true
                if tag.count > 1 {
                    extractedWhitelistMessage = tag[1]
                }
            default:
                break
            }
        }
        
        self.url = extractedUrl
        self.name = extractedName.isEmpty ? Self.extractServerName(from: extractedUrl) : extractedName
        self.isPaid = extractedIsPaid
        self.isWhitelisted = extractedIsWhitelisted
        self.whitelistMessage = extractedWhitelistMessage
        self.paidMessage = extractedPaidMessage
    }
    
    /// Extracts a display name from the server URL
    private static func extractServerName(from url: String) -> String {
        // Remove protocol
        var name = url
        if let range = name.range(of: "://") {
            name = String(name[range.upperBound...])
        }
        
        // Remove trailing slash
        if name.hasSuffix("/") {
            name = String(name.dropLast())
        }
        
        // Remove www.
        if name.hasPrefix("www.") {
            name = String(name.dropFirst(4))
        }
        
        // Take first part before any path
        if let firstSlash = name.firstIndex(of: "/") {
            name = String(name[..<firstSlash])
        }
        
        return name
    }
    
    /// Display subtitle for the server
    public var subtitle: String? {
        if isPaid && isWhitelisted {
            return "Paid & Whitelisted"
        } else if isPaid {
            return "Paid"
        } else if isWhitelisted {
            return "Whitelist Required"
        } else {
            return "Free"
        }
    }
    
    /// Combined access message
    public var accessMessage: String? {
        if let paidMsg = paidMessage, let whitelistMsg = whitelistMessage {
            return "\(paidMsg)\n\(whitelistMsg)"
        } else if let paidMsg = paidMessage {
            return paidMsg
        } else if let whitelistMsg = whitelistMessage {
            return whitelistMsg
        } else if isPaid || isWhitelisted {
            return "Access restricted"
        }
        return nil
    }
}

/// Manages Blossom server lists for the current user and discovers public servers
@Observable
public class NDKBlossomServerManager {
    private static let defaultServer = "https://blossom.primal.net"

    public private(set) var userServers: [String] = [NDKBlossomServerManager.defaultServer]
    public private(set) var discoveredServers: [NDKBlossomServerInfo] = []
    public private(set) var isLoading = false

    private let ndk: NDK
    private var discoveryTask: Task<Void, Never>?

    public init(ndk: NDK) {
        self.ndk = ndk
        Task {
            await loadUserServers()
            await loadDiscoveredServers()
        }
    }
    
    deinit {
        discoveryTask?.cancel()
    }
    
    // MARK: - User Server Management (kind 10063)
    
    /// Load user's personal server list from kind 10063 events
    public func loadUserServers() async {
        guard let signer = ndk.signer else {
            // Fallback to default server
            userServers = [Self.defaultServer]
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get the public key from signer
            let pubkey = try await signer.pubkey
            
            // Fetch user's blossom server list event (kind 10063)
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.blossomServerList]
            )
            
            // Use observe to get the event
            let dataSource = ndk.subscribe(filter: filter, maxAge: 300, cachePolicy: .cacheWithNetwork)
            
            var foundEvent = false
            for await event in dataSource.events {
                parseUserServersFromEvent(event)
                foundEvent = true
                break // We only need the first event
            }
            
            if !foundEvent {
                // No server list found, use default
                userServers = [Self.defaultServer]
            }
        } catch {
            NDKLogger.log(.error, category: .general, "NDKBlossomServerManager - Failed to fetch user server list: \(error)")
            userServers = [Self.defaultServer]
        }
    }
    
    private func parseUserServersFromEvent(_ event: NDKEvent) {
        var serverList: [String] = []
        
        // Parse server tags
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "server" {
                let serverUrl = tag[1]
                if !serverUrl.isEmpty {
                    serverList.append(serverUrl)
                }
            }
        }
        
        // Update servers list
        userServers = serverList.isEmpty ? [Self.defaultServer] : serverList
    }
    
    /// Add a server to the user's list
    public func addUserServer(_ serverUrl: String) {
        guard !userServers.contains(serverUrl) else { return }
        userServers.append(serverUrl)
        Task {
            await publishUserServerList()
        }
    }
    
    /// Remove a server from the user's list
    public func removeUserServer(_ serverUrl: String) {
        userServers.removeAll { $0 == serverUrl }
        if userServers.isEmpty {
            userServers = [Self.defaultServer]
        }
        Task {
            await publishUserServerList()
        }
    }
    
    /// Reorder user servers
    public func moveUserServer(from source: IndexSet, to destination: Int) {
        var newServers = userServers
        for index in source.sorted(by: >) {
            let server = newServers.remove(at: index)
            let adjustedDestination = destination > index ? destination - 1 : destination
            newServers.insert(server, at: adjustedDestination)
        }
        userServers = newServers
        Task {
            await publishUserServerList()
        }
    }
    
    private func publishUserServerList() async {
        guard let signer = ndk.signer else { return }
        
        do {
            // Create server list event (kind 10063)
            let event = try await NDKEventBuilder(ndk: ndk)
                .kind(EventKind.blossomServerList)
                .content("")
                .tags(userServers.map { ["server", $0] })
                .build(signer: signer)
            
            _ = try await ndk.publish(event)
            
            NDKLogger.log(.info, category: .general, "NDKBlossomServerManager - Published user server list")
        } catch {
            NDKLogger.log(.error, category: .general, "NDKBlossomServerManager - Failed to publish server list: \(error)")
        }
    }
    
    // MARK: - Server Discovery (kind 36363)
    
    /// Load discovered Blossom servers from kind 36363 events
    public func loadDiscoveredServers() async {
        discoveryTask?.cancel()
        discoveryTask = Task {
            NDKLogger.log(.debug, category: .general, "NDKBlossomServerManager - Starting to fetch kind 36363 events...")
            
            // Create filter for Blossom server discovery events (kind 36363)
            let filter = NDKFilter(
                kinds: [EventKind.blossomServerAnnouncement],
                limit: 50
            )
            
            // Use observe with cache-first approach
            let dataSource = ndk.subscribe(filter: filter, maxAge: 3600, cachePolicy: .cacheWithNetwork)
            
            var serverInfos: [NDKBlossomServerInfo] = []
            var seenUrls = Set<String>()
            
            for await event in dataSource.events {
                if Task.isCancelled { break }
                
                let serverInfo = NDKBlossomServerInfo(from: event)
                
                // Only add if we haven't seen this URL before and it's valid
                if !serverInfo.url.isEmpty && !seenUrls.contains(serverInfo.url) {
                    seenUrls.insert(serverInfo.url)
                    serverInfos.append(serverInfo)
                    
                    NDKLogger.log(.debug, category: .general, "NDKBlossomServerManager - Found server: \(serverInfo.name) at \(serverInfo.url)")
                    
                    // Update UI incrementally
                    let sortedServers = serverInfos.sorted { server1, server2 in
                        // Sort free servers first, then by name
                        if server1.isPaid == server2.isPaid && server1.isWhitelisted == server2.isWhitelisted {
                            return server1.name < server2.name
                        }
                        if server1.isPaid != server2.isPaid {
                            return !server1.isPaid
                        }
                        return !server1.isWhitelisted
                    }
                    await MainActor.run {
                        discoveredServers = sortedServers
                    }
                }
            }
            
            NDKLogger.log(.info, category: .general, "NDKBlossomServerManager - Finished loading discovered servers. Found \(serverInfos.count) servers.")
        }
    }
    
    // MARK: - Upload Functionality
    
    /// Upload data to user's selected servers with fallback
    public func uploadToUserServers(data: Data, mimeType: String) async throws -> BlossomBlob {
        guard !userServers.isEmpty else {
            throw BlossomManagerError.noServersConfigured
        }
        
        let client = BlossomClient()
        
        // Try uploading to each server until one succeeds
        var lastError: Error?
        
        for serverUrl in userServers {
            do {
                let result = try await client.uploadWithAuth(
                    data: data,
                    mimeType: mimeType,
                    to: serverUrl,
                    signer: try ndk.requireSigner(),
                    ndk: ndk
                )
                return result
            } catch {
                lastError = error
                continue
            }
        }
        
        throw BlossomManagerError.allUploadsFailed(lastError?.localizedDescription ?? "No successful uploads")
    }
    
    /// Upload to specific servers
    public func uploadToServers(_ serverUrls: [String], data: Data, mimeType: String) async throws -> [BlossomBlob] {
        guard !serverUrls.isEmpty else {
            throw BlossomManagerError.noServersConfigured
        }
        
        let client = BlossomClient()
        var results: [BlossomBlob] = []
        
        for serverUrl in serverUrls {
            do {
                let result = try await client.uploadWithAuth(
                    data: data,
                    mimeType: mimeType,
                    to: serverUrl,
                    signer: try ndk.requireSigner(),
                    ndk: ndk
                )
                results.append(result)
            } catch {
                NDKLogger.log(.warning, category: .general, "NDKBlossomServerManager - Upload to \(serverUrl) failed: \(error)")
                // Continue with other servers
            }
        }
        
        if results.isEmpty {
            throw BlossomManagerError.allUploadsFailed("All servers failed")
        }
        
        return results
    }
    
    // MARK: - Convenience Properties
    
    /// Get all user servers for fallback upload attempts
    public var allUserServers: [String] {
        userServers.isEmpty ? [Self.defaultServer] : userServers
    }
    
    /// Get discovered servers that are free to use
    public var freeServers: [NDKBlossomServerInfo] {
        discoveredServers.filter { !$0.isPaid && !$0.isWhitelisted }
    }
    
    /// Get discovered servers that require payment
    public var paidServers: [NDKBlossomServerInfo] {
        discoveredServers.filter { $0.isPaid }
    }
    
    /// Get discovered servers that require whitelist
    public var whitelistedServers: [NDKBlossomServerInfo] {
        discoveredServers.filter { $0.isWhitelisted }
    }
}

// MARK: - Error Types

public enum BlossomManagerError: LocalizedError {
    case noServersConfigured
    case allUploadsFailed(String)
    case notAuthenticated
    
    public var errorDescription: String? {
        switch self {
        case .noServersConfigured:
            return "No Blossom servers configured"
        case .allUploadsFailed(let details):
            return "All uploads failed: \(details)"
        case .notAuthenticated:
            return "User must be authenticated to manage Blossom servers"
        }
    }
}