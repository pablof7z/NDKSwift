import Foundation
import NDKSwift

actor RelayMonitor {
    struct RelayStats {
        var url: String
        var status: RelayStatus
        var sentEvents: Int = 0
        var receivedEvents: Int = 0
        var lastActivity: Date?
    }
    
    enum RelayStatus {
        case connecting
        case connected
        case disconnected
        case error(String)
    }
    
    private var relayStats: [String: RelayStats] = [:]
    private var eventCallbacks: [(RelayStats) -> Void] = []
    
    func updateRelayStatus(url: String, status: RelayStatus) {
        if relayStats[url] == nil {
            relayStats[url] = RelayStats(url: url, status: status)
        } else {
            relayStats[url]?.status = status
        }
        relayStats[url]?.lastActivity = Date()
        notifyCallbacks()
    }
    
    func incrementSentEvents(url: String) {
        if relayStats[url] == nil {
            relayStats[url] = RelayStats(url: url, status: .disconnected)
        }
        relayStats[url]?.sentEvents += 1
        relayStats[url]?.lastActivity = Date()
        notifyCallbacks()
    }
    
    func incrementReceivedEvents(url: String) {
        if relayStats[url] == nil {
            relayStats[url] = RelayStats(url: url, status: .disconnected)
        }
        relayStats[url]?.receivedEvents += 1
        relayStats[url]?.lastActivity = Date()
        notifyCallbacks()
    }
    
    func getAllStats() -> [RelayStats] {
        Array(relayStats.values).sorted { $0.url < $1.url }
    }
    
    func onUpdate(_ callback: @escaping (RelayStats) -> Void) {
        eventCallbacks.append(callback)
    }
    
    private func notifyCallbacks() {
        let stats = Array(relayStats.values)
        for callback in eventCallbacks {
            for stat in stats {
                callback(stat)
            }
        }
    }
}