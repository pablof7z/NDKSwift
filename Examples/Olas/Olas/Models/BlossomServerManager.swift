import Foundation
import NDKSwift
import SwiftUI

@MainActor
class BlossomServerManager: ObservableObject {
    @Published var servers: [BlossomServerInfo] = []
    @Published var selectedServers: Set<String> = []
    @Published var isLoading = false
    
    private var ndk: NDK?
    
    // Default Blossom servers for Olas
    private let defaultServers = [
        "https://files.hzrd149.com",
        "https://cdn.satellite.earth",
        "https://nostr.build"
    ]
    
    // Key for storing user preferences
    private static let selectedServersKey = "OlasSelectedBlossomServers"
    
    init(ndk: NDK?) {
        self.ndk = ndk
        loadSelectedServers()
        Task {
            await loadServerInfo()
        }
    }
    
    private func loadSelectedServers() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.selectedServersKey) {
            selectedServers = Set(saved)
        } else {
            // Default to first server if none selected
            selectedServers = [defaultServers.first!]
        }
    }
    
    private func saveSelectedServers() {
        UserDefaults.standard.set(Array(selectedServers), forKey: Self.selectedServersKey)
    }
    
    func toggleServer(_ serverURL: String) {
        if selectedServers.contains(serverURL) {
            selectedServers.remove(serverURL)
        } else {
            selectedServers.insert(serverURL)
        }
        saveSelectedServers()
    }
    
    private func loadServerInfo() async {
        isLoading = true
        defer { isLoading = false }
        
        var serverInfos: [BlossomServerInfo] = []
        
        for serverURL in defaultServers {
            let info = BlossomServerInfo(
                url: serverURL,
                name: serverName(for: serverURL),
                isAvailable: true, // We'll implement health checks later
                maxUploadSize: nil
            )
            serverInfos.append(info)
        }
        
        servers = serverInfos
    }
    
    private func serverName(for url: String) -> String {
        if url.contains("hzrd149") {
            return "hzrd149's Files"
        } else if url.contains("satellite") {
            return "Satellite CDN"
        } else if url.contains("nostr.build") {
            return "nostr.build"
        } else {
            return URL(string: url)?.host ?? url
        }
    }
    
    func uploadToSelectedServers(data: Data, mimeType: String) async throws -> [BlossomUploadResult] {
        guard let ndk = ndk, ndk.signer != nil else {
            throw BlossomError.notAuthenticated
        }
        
        let selectedServerURLs = Array(selectedServers)
        guard !selectedServerURLs.isEmpty else {
            throw BlossomError.noServersSelected
        }
        
        var results: [BlossomUploadResult] = []
        
        for serverURL in selectedServerURLs {
            do {
                let blobs = try await ndk.uploadToBlossom(
                    data: data,
                    mimeType: mimeType,
                    servers: [serverURL]
                )
                
                if let firstBlob = blobs.first {
                    results.append(BlossomUploadResult(
                        serverURL: serverURL,
                        fileURL: firstBlob.url,
                        success: true,
                        error: nil
                    ))
                } else {
                    throw BlossomError.uploadFailed("No blob returned from server")
                }
            } catch {
                results.append(BlossomUploadResult(
                    serverURL: serverURL,
                    fileURL: nil,
                    success: false,
                    error: error
                ))
            }
        }
        
        // If at least one upload succeeded, return results
        if results.contains(where: { $0.success }) {
            return results
        } else {
            // All uploads failed
            throw BlossomError.allUploadsFailed(results)
        }
    }
}

// MARK: - Supporting Types

struct BlossomServerInfo: Identifiable {
    let id = UUID()
    let url: String
    let name: String
    let isAvailable: Bool
    let maxUploadSize: Int64?
}

struct BlossomUploadResult {
    let serverURL: String
    let fileURL: String?
    let success: Bool
    let error: Error?
}

enum BlossomError: LocalizedError {
    case notAuthenticated
    case noServersSelected
    case allUploadsFailed([BlossomUploadResult])
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to upload files"
        case .noServersSelected:
            return "Please select at least one server"
        case .allUploadsFailed(let results):
            let errors = results.compactMap { $0.error?.localizedDescription }.joined(separator: ", ")
            return "All uploads failed: \(errors)"
        case .uploadFailed(let message):
            return message
        }
    }
}