import Foundation
import NDKSwift
import SwiftUI

/// Shared BlossomServerManager for use across multiple apps
@MainActor
@Observable
public class BlossomServerManager {
    public var servers: [String] = []
    public var isLoading = false
    public var suggestedServers: [BlossomServerInfo] = []
    
    private let ndk: NDK?
    private let defaultServer = "https://blossom.primal.net"
    private let userDefaultsKey: String
    private var suggestionsTask: Task<Void, Never>?
    
    public struct BlossomServerInfo {
        public let url: String
        public let description: String
        public let pubkey: String
    }
    
    public init(ndk: NDK?, appName: String) {
        self.ndk = ndk
        self.userDefaultsKey = "\(appName)BlossomServers"
        loadServers()
        loadSuggestedServers()
    }
    
    deinit {
        suggestionsTask?.cancel()
    }
    
    // MARK: - Server Management
    
    public func loadServers() {
        guard let ndk = ndk, let signer = ndk.signer else {
            // Fallback to default server
            servers = [defaultServer]
            return
        }
        
        isLoading = true
        
        Task {
            do {
                // Get the public key from signer
                let pubkey = try await signer.pubkey
                
                // Fetch user's blossom server list event (kind 10063)
                let filter = NDKFilter(
                    authors: [pubkey],
                    kinds: [10063],
                    limit: 1
                )
                
                // Use observe to get the event
                let dataSource = ndk.observe(filter: filter, maxAge: 300, cachePolicy: .cacheWithNetwork)
                
                for await events in dataSource.values {
                    if let event = events.first {
                        // Parse servers from tags
                        let serverUrls = event.tags
                            .filter { $0.count > 1 && $0[0] == "server" }
                            .map { $0[1] }
                            .filter { !$0.isEmpty }
                        
                        if !serverUrls.isEmpty {
                            servers = serverUrls
                            saveServersToUserDefaults(serverUrls)
                        } else {
                            loadServersFromUserDefaults()
                        }
                    } else {
                        loadServersFromUserDefaults()
                    }
                    break
                }
                
                isLoading = false
            } catch {
                print("Error loading blossom servers: \(error)")
                loadServersFromUserDefaults()
                isLoading = false
            }
        }
    }
    
    private func loadServersFromUserDefaults() {
        if let savedServers = UserDefaults.standard.stringArray(forKey: userDefaultsKey),
           !savedServers.isEmpty {
            servers = savedServers
        } else {
            servers = [defaultServer]
        }
    }
    
    private func saveServersToUserDefaults(_ servers: [String]) {
        UserDefaults.standard.set(servers, forKey: userDefaultsKey)
    }
    
    public func addServer(_ url: String) {
        guard !url.isEmpty, !servers.contains(url) else { return }
        servers.append(url)
        saveServersToUserDefaults(servers)
        Task {
            await publishServerList()
        }
    }
    
    public func removeServer(_ url: String) {
        servers.removeAll { $0 == url }
        if servers.isEmpty {
            servers = [defaultServer]
        }
        saveServersToUserDefaults(servers)
        Task {
            await publishServerList()
        }
    }
    
    // MARK: - Publishing
    
    private func publishServerList() async {
        guard let ndk = ndk, let signer = ndk.signer else { return }
        
        do {
            let tags = servers.map { ["server", $0] }
            
            let event = NDKEvent(
                kind: 10063,
                content: "",
                tags: tags
            )
            
            try await event.sign(with: signer)
            try await ndk.publish(event: event)
            print("Published updated blossom server list")
        } catch {
            print("Error publishing blossom server list: \(error)")
        }
    }
    
    // MARK: - Suggested Servers
    
    private func loadSuggestedServers() {
        suggestionsTask?.cancel()
        suggestionsTask = Task {
            // Hardcoded suggestions for now
            suggestedServers = [
                BlossomServerInfo(
                    url: "https://blossom.primal.net",
                    description: "Primal's Blossom server",
                    pubkey: ""
                ),
                BlossomServerInfo(
                    url: "https://blossom.satellite.earth",
                    description: "Satellite Earth's Blossom server",
                    pubkey: ""
                ),
                BlossomServerInfo(
                    url: "https://blossom.nostr.wine",
                    description: "Nostr Wine's Blossom server",
                    pubkey: ""
                )
            ]
        }
    }
}