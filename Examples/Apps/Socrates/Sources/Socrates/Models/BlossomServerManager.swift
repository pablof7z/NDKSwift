import Foundation
import NDKSwift

@MainActor
class BlossomServerManager: ObservableObject {
    @Published var servers: [String] = []
    @Published var isLoading = false
    
    private let ndk: NDK?
    private let defaultServer = "https://blossom.primal.net"
    private static let userDefaultsKey = "SocratesBlossomServers"
    
    init(ndk: NDK?) {
        self.ndk = ndk
        loadServers()
    }
    
    // MARK: - Server Management
    
    func loadServers() {
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
                
                var foundEvent = false
                for await event in dataSource.events {
                    parseServersFromEvent(event)
                    foundEvent = true
                    break // We only need the first event
                }
                
                if !foundEvent {
                    // No server list found, use default
                    servers = [defaultServer]
                }
            } catch {
                print("Failed to fetch blossom server list: \(error)")
                servers = [defaultServer]
            }
            
            isLoading = false
        }
    }
    
    private func parseServersFromEvent(_ event: NDKEvent) {
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
        servers = serverList.isEmpty ? [defaultServer] : serverList
        
        // Save to UserDefaults
        saveToUserDefaults()
    }
    
    // MARK: - Persistence
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(servers, forKey: Self.userDefaultsKey)
    }
    
    private func loadFromUserDefaults() {
        if let savedServers = UserDefaults.standard.stringArray(forKey: Self.userDefaultsKey),
           !savedServers.isEmpty {
            servers = savedServers
        } else {
            servers = [defaultServer]
        }
    }
    
    // MARK: - Server Management UI
    
    func addServer(_ serverUrl: String) {
        guard !servers.contains(serverUrl) else { return }
        servers.append(serverUrl)
        saveToUserDefaults()
        publishServerList()
    }
    
    func removeServer(_ serverUrl: String) {
        servers.removeAll { $0 == serverUrl }
        if servers.isEmpty {
            servers = [defaultServer]
        }
        saveToUserDefaults()
        publishServerList()
    }
    
    private func publishServerList() {
        guard let ndk = ndk else { return }
        
        Task {
            do {
                // Create server list event (kind 10063)
                let (_, _) = try await ndk.publish { builder in
                    var eventBuilder = builder.kind(10063)
                    
                    // Add server tags
                    for server in servers {
                        eventBuilder = eventBuilder.tag(["server", server])
                    }
                    
                    return eventBuilder
                }
                
                print("Published blossom server list")
            } catch {
                print("Failed to publish server list: \(error)")
            }
        }
    }
    
    // MARK: - Convenience
    
    /// Get all servers for fallback upload attempts
    var allServers: [String] {
        servers.isEmpty ? [defaultServer] : servers
    }
}