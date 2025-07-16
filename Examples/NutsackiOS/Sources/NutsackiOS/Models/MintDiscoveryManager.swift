import Foundation
import NDKSwift

/// Manager for discovering Cashu mints using NIP-87
@MainActor
class MintDiscoveryManager {
    private let ndk: NDK
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Discover mints through NIP-87 announcements and recommendations with streaming updates
    func discoverMintsStream() -> AsyncStream<[DiscoveredMint]> {
        AsyncStream { continuation in
            Task {
                var discoveredMints: [DiscoveredMint] = []
                var mintsByURL: [URL: DiscoveredMint] = [:]
                
                // Subscribe to mint announcements (kind: 38172)
                let announcementFilter = NDKFilter(
                    kinds: [38172],
                    limit: 100
                )
                
                let announcementSub = await ndk.subscribe(filters: [announcementFilter])
                
                // Subscribe to recommendations (kind: 38000)
                let recommendationFilter = NDKFilter(
                    kinds: [38000],
                    limit: 100
                )
                
                let recommendationSub = await ndk.subscribe(filters: [recommendationFilter])
                
                // Process announcements as they stream in
                Task {
                    do {
                        for try await announcementEvent in announcementSub {
                            let announcement = NDKCashuMintAnnouncement(event: announcementEvent)
                        
                        if let mintURL = announcement.mintURL,
                           let url = URL(string: mintURL) {
                            
                            let discoveredMint = DiscoveredMint(
                                url: url,
                                name: announcement.name,
                                description: announcement.description,
                                contact: announcement.contact,
                                pubkey: announcement.event.pubkey,
                                supportedNuts: announcement.supportedNuts,
                                network: announcement.network ?? "mainnet",
                                recommendedBy: nil,
                                recommendationReason: nil,
                                announcementEvent: announcementEvent,
                                recommendationEvent: nil
                            )
                            
                            mintsByURL[url] = discoveredMint
                            
                            // Rebuild and sort the array
                            discoveredMints = Array(mintsByURL.values).sorted { first, second in
                                if first.recommendedBy != nil && second.recommendedBy == nil {
                                    return true
                                } else if first.recommendedBy == nil && second.recommendedBy != nil {
                                    return false
                                }
                                let firstDate = first.announcementEvent?.createdAt ?? 0
                                let secondDate = second.announcementEvent?.createdAt ?? 0
                                return firstDate > secondDate
                            }
                            
                            continuation.yield(discoveredMints)
                        }
                    }
                    } catch {
                        // Log error but don't stop the stream
                        print("Error processing announcement stream: \(error)")
                    }
                }
                
                // Process recommendations as they stream in
                Task {
                    do {
                        for try await recommendationEvent in recommendationSub {
                        let recommendation = NDKMintRecommendation(event: recommendationEvent)
                        
                        if let mintURL = recommendation.mintURL,
                           let url = URL(string: mintURL) {
                            
                            if var existingMint = mintsByURL[url] {
                                // Update existing mint with recommendation
                                existingMint.recommendedBy = recommendationEvent.pubkey
                                existingMint.recommendationReason = recommendation.reason
                                existingMint.recommendationEvent = recommendationEvent
                                mintsByURL[url] = existingMint
                            } else {
                                // Create new mint from recommendation only
                                let discoveredMint = DiscoveredMint(
                                    url: url,
                                    name: nil,
                                    description: recommendation.reason,
                                    contact: nil,
                                    pubkey: recommendationEvent.pubkey,
                                    supportedNuts: [],
                                    network: "mainnet",
                                    recommendedBy: recommendationEvent.pubkey,
                                    recommendationReason: recommendation.reason,
                                    announcementEvent: nil,
                                    recommendationEvent: recommendationEvent
                                )
                                mintsByURL[url] = discoveredMint
                            }
                            
                            // Rebuild and sort the array
                            discoveredMints = Array(mintsByURL.values).sorted { first, second in
                                if first.recommendedBy != nil && second.recommendedBy == nil {
                                    return true
                                } else if first.recommendedBy == nil && second.recommendedBy != nil {
                                    return false
                                }
                                let firstDate = first.announcementEvent?.createdAt ?? 0
                                let secondDate = second.announcementEvent?.createdAt ?? 0
                                return firstDate > secondDate
                            }
                            
                            continuation.yield(discoveredMints)
                        }
                    }
                    } catch {
                        // Log error but don't stop the stream
                        print("Error processing recommendation stream: \(error)")
                    }
                }
                
                // Clean up on cancellation
                continuation.onTermination = { @Sendable _ in
                    Task {
                        await announcementSub.close()
                        await recommendationSub.close()
                    }
                }
            }
        }
    }
}

/// Represents a discovered mint with all available information
struct DiscoveredMint {
    let url: URL
    let name: String?
    let description: String?
    let contact: String?
    let pubkey: String
    let supportedNuts: [String]
    let network: String
    var recommendedBy: String?
    var recommendationReason: String?
    let announcementEvent: NDKEvent?
    var recommendationEvent: NDKEvent?
    
    /// Check if this mint is on mainnet
    var isMainnet: Bool {
        network == "mainnet"
    }
    
    /// Get a display name for the mint
    var displayName: String {
        name ?? url.host ?? url.absoluteString
    }
    
    /// Check if mint supports a specific NUT
    func supports(nut: String) -> Bool {
        supportedNuts.contains(nut)
    }
}