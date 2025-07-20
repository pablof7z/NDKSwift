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
                
                // Use declarative data source for announcements
                let announcementDataSource = ndk.observe(
                    filter: announcementFilter,
                    maxAge: 0, // Real-time updates
                    cachePolicy: .cacheWithNetwork
                )
                
                // Subscribe to recommendations (kind: 38000)
                let recommendationFilter = NDKFilter(
                    kinds: [38000],
                    limit: 100
                )
                
                // Use declarative data source for recommendations
                let recommendationDataSource = ndk.observe(
                    filter: recommendationFilter,
                    maxAge: 0, // Real-time updates
                    cachePolicy: .cacheWithNetwork
                )
                
                // Process announcements as they stream in
                Task {
                    do {
                        for await announcementEvent in announcementDataSource.events {
                            let announcement = NDKCashuMintAnnouncement(event: announcementEvent)
                        
                        if let mintURL = announcement.mintURL,
                           let url = URL(string: mintURL) {
                            
                            let discoveredMint = DiscoveredMint(
                                url: url.absoluteString,
                                name: announcement.name ?? url.host ?? "Unknown Mint",
                                announcedBy: announcement.event.pubkey,
                                announcementId: announcementEvent.id,
                                announcementCreatedAt: announcementEvent.createdAt,
                                recommendedBy: [],
                                description: announcement.description,
                                pubkey: announcement.event.pubkey
                            )
                            
                            mintsByURL[url] = discoveredMint
                            
                            // Rebuild and sort the array
                            discoveredMints = Array(mintsByURL.values).sorted { first, second in
                                if !first.recommendedBy.isEmpty && second.recommendedBy.isEmpty {
                                    return true
                                } else if first.recommendedBy.isEmpty && !second.recommendedBy.isEmpty {
                                    return false
                                }
                                let firstDate = first.announcementCreatedAt ?? 0
                                let secondDate = second.announcementCreatedAt ?? 0
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
                        for await recommendationEvent in recommendationDataSource.events {
                        let recommendation = NDKMintRecommendation(event: recommendationEvent)
                        
                        if let mintURL = recommendation.mintURL,
                           let url = URL(string: mintURL) {
                            
                            if var existingMint = mintsByURL[url] {
                                // Update existing mint with recommendation
                                if !existingMint.recommendedBy.contains(recommendationEvent.pubkey) {
                                    existingMint.recommendedBy.append(recommendationEvent.pubkey)
                                }
                                mintsByURL[url] = existingMint
                            } else {
                                // Create new mint from recommendation only
                                let discoveredMint = DiscoveredMint(
                                    url: url.absoluteString,
                                    name: url.host ?? "Unknown Mint",
                                    announcedBy: nil,
                                    announcementId: nil,
                                    announcementCreatedAt: nil,
                                    recommendedBy: [recommendationEvent.pubkey],
                                    description: recommendation.reason,
                                    pubkey: nil
                                )
                                mintsByURL[url] = discoveredMint
                            }
                            
                            // Rebuild and sort the array
                            discoveredMints = Array(mintsByURL.values).sorted { first, second in
                                if !first.recommendedBy.isEmpty && second.recommendedBy.isEmpty {
                                    return true
                                } else if first.recommendedBy.isEmpty && !second.recommendedBy.isEmpty {
                                    return false
                                }
                                let firstDate = first.announcementCreatedAt ?? 0
                                let secondDate = second.announcementCreatedAt ?? 0
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
                    // Data sources clean up automatically
                }
            }
        }
    }
}

// DiscoveredMint is now defined in WalletDataSources.swift