import Foundation

/// Configuration for connection reliability features
public struct NDKConnectionConfig: Sendable {
    /// Whether to enable WebSocket state monitoring
    public let enableStateMonitoring: Bool

    /// Whether to enable periodic health checks (ping/pong)
    public let enableHealthChecks: Bool

    /// Interval between health checks in seconds
    public let healthCheckInterval: TimeInterval

    /// Whether to enable app lifecycle monitoring (iOS/macOS)
    public let enableLifecycleMonitoring: Bool

    /// Whether to enable network change monitoring
    public let enableNetworkMonitoring: Bool

    /// Timeout for health check responses in seconds
    public let healthCheckTimeout: TimeInterval

    /// Whether to automatically reconnect on network changes
    public let autoReconnectOnNetworkChange: Bool

    /// Whether to automatically reconnect when app returns to foreground
    public let autoReconnectOnForeground: Bool

    /// Initialize with custom configuration
    public init(
        enableStateMonitoring: Bool = true,
        enableHealthChecks: Bool = true,
        healthCheckInterval: TimeInterval = 30,
        enableLifecycleMonitoring: Bool = true,
        enableNetworkMonitoring: Bool = true,
        healthCheckTimeout: TimeInterval = 10,
        autoReconnectOnNetworkChange: Bool = true,
        autoReconnectOnForeground: Bool = true
    ) {
        self.enableStateMonitoring = enableStateMonitoring
        self.enableHealthChecks = enableHealthChecks
        self.healthCheckInterval = healthCheckInterval
        self.enableLifecycleMonitoring = enableLifecycleMonitoring
        self.enableNetworkMonitoring = enableNetworkMonitoring
        self.healthCheckTimeout = healthCheckTimeout
        self.autoReconnectOnNetworkChange = autoReconnectOnNetworkChange
        self.autoReconnectOnForeground = autoReconnectOnForeground
    }

    /// Default configuration with all features enabled
    public static let `default` = NDKConnectionConfig()

    /// Minimal configuration with only state monitoring
    public static let minimal = NDKConnectionConfig(
        enableStateMonitoring: true,
        enableHealthChecks: false,
        enableLifecycleMonitoring: false,
        enableNetworkMonitoring: false
    )

    /// Aggressive configuration with more frequent health checks
    public static let aggressive = NDKConnectionConfig(
        enableStateMonitoring: true,
        enableHealthChecks: true,
        healthCheckInterval: 15,
        enableLifecycleMonitoring: true,
        enableNetworkMonitoring: true,
        healthCheckTimeout: 5
    )

    /// Conservative configuration with less frequent checks to save battery
    public static let conservative = NDKConnectionConfig(
        enableStateMonitoring: true,
        enableHealthChecks: true,
        healthCheckInterval: 60,
        enableLifecycleMonitoring: true,
        enableNetworkMonitoring: true,
        healthCheckTimeout: 15
    )
}
