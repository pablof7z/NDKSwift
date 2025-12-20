import Foundation
import Network

/// Protocol for receiving network change notifications
public protocol NDKNetworkMonitorDelegate: AnyObject, Sendable {
    /// Called when network becomes available
    func networkMonitorDidGainConnectivity()

    /// Called when network becomes unavailable
    func networkMonitorDidLoseConnectivity()

    /// Called when network path changes (e.g., WiFi to cellular)
    func networkMonitorDidChangeNetworkType()
}

/// Monitors network connectivity changes using NWPathMonitor
public actor NDKNetworkMonitor {
    public weak var delegate: NDKNetworkMonitorDelegate?

    private var pathMonitor: NWPathMonitor?
    private var monitorQueue: DispatchQueue?
    private var isMonitoring = false
    private var currentPath: NWPath?
    private var wasConnected = false

    public init() {}

    /// Start monitoring network changes
    public func startMonitoring() {
        guard !isMonitoring else {
            NDKLogger.log(.debug, category: .connection, "🌐 Network monitor already running")
            return
        }

        let queue = DispatchQueue(label: "com.ndkswift.networkmonitor", qos: .utility)
        monitorQueue = queue

        let monitor = NWPathMonitor()
        pathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handlePathUpdate(path)
            }
        }

        monitor.start(queue: queue)
        isMonitoring = true

        NDKLogger.log(.info, category: .connection, "🌐 Started network connectivity monitoring")
    }

    /// Stop monitoring network changes
    public func stopMonitoring() {
        guard isMonitoring else { return }

        pathMonitor?.cancel()
        pathMonitor = nil
        monitorQueue = nil
        isMonitoring = false

        NDKLogger.log(.info, category: .connection, "🌐 Stopped network connectivity monitoring")
    }

    /// Check if network is currently available
    public var isConnected: Bool {
        currentPath?.status == .satisfied
    }

    /// Get current network interface type
    public var interfaceType: NetworkInterfaceType {
        guard let path = currentPath else { return .unknown }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .other
        }
    }

    private func handlePathUpdate(_ path: NWPath) async {
        let previousPath = currentPath
        currentPath = path

        let isNowConnected = path.status == .satisfied
        let wasExpensive = previousPath?.isExpensive ?? false
        let isNowExpensive = path.isExpensive

        NDKLogger.log(
            .debug,
            category: .connection,
            "🌐 Network path updated - Status: \(path.status), Expensive: \(isNowExpensive)"
        )

        // Check for connectivity changes
        if !wasConnected && isNowConnected {
            wasConnected = true
            NDKLogger.log(.info, category: .connection, "🌐 Network connectivity gained")
            await delegate?.networkMonitorDidGainConnectivity()
        } else if wasConnected && !isNowConnected {
            wasConnected = false
            NDKLogger.log(.warning, category: .connection, "🌐 Network connectivity lost")
            await delegate?.networkMonitorDidLoseConnectivity()
        }

        // Check for network type changes (only when connected)
        if isNowConnected, let previousPath = previousPath {
            let previousType = getInterfaceType(from: previousPath)
            let currentType = getInterfaceType(from: path)

            if previousType != currentType || wasExpensive != isNowExpensive {
                NDKLogger.log(
                    .info,
                    category: .connection,
                    "🌐 Network type changed from \(previousType) to \(currentType)"
                )
                await delegate?.networkMonitorDidChangeNetworkType()
            }
        }
    }

    private func getInterfaceType(from path: NWPath) -> NetworkInterfaceType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .other
        }
    }

    deinit {
        pathMonitor?.cancel()
    }
}

/// Network interface type
public enum NetworkInterfaceType: Sendable, Equatable {
    case wifi
    case cellular
    case ethernet
    case other
    case unknown
}
