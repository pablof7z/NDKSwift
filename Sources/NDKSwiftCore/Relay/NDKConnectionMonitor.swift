import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Protocol for receiving app lifecycle notifications
public protocol NDKConnectionMonitorDelegate: AnyObject, Sendable {
    /// Called when the app enters the background
    func connectionMonitorDidEnterBackground()

    /// Called when the app returns to the foreground
    func connectionMonitorDidEnterForeground()

    /// Called when the app becomes active
    func connectionMonitorDidBecomeActive()

    /// Called when the app will resign active
    func connectionMonitorWillResignActive()
}

/// Monitors app lifecycle events to handle connection state
public actor NDKConnectionMonitor {
    public weak var delegate: NDKConnectionMonitorDelegate?

    private var isMonitoring = false

    #if canImport(UIKit) || canImport(AppKit)
    private var observers: [NSObjectProtocol] = []
    #endif

    public init() {}

    /// Start monitoring app lifecycle events
    public func startMonitoring() {
        guard !isMonitoring else {
            NDKLogger.log(.debug, category: .connection, "📱 Connection monitor already running")
            return
        }

        isMonitoring = true
        setupNotificationObservers()
        NDKLogger.log(.info, category: .connection, "📱 Started connection lifecycle monitoring")
    }

    /// Stop monitoring app lifecycle events
    public func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        removeNotificationObservers()
        NDKLogger.log(.info, category: .connection, "📱 Stopped connection lifecycle monitoring")
    }

    private func setupNotificationObservers() {
        #if canImport(UIKit)
        setupUIKitObservers()
        #elseif canImport(AppKit)
        setupAppKitObservers()
        #endif
    }

    #if canImport(UIKit)
    private func setupUIKitObservers() {
        let center = NotificationCenter.default

        // App entering background
        let backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleDidEnterBackground()
            }
        }
        observers.append(backgroundObserver)

        // App entering foreground
        let foregroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleWillEnterForeground()
            }
        }
        observers.append(foregroundObserver)

        // App becoming active
        let activeObserver = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleDidBecomeActive()
            }
        }
        observers.append(activeObserver)

        // App resigning active
        let resignObserver = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleWillResignActive()
            }
        }
        observers.append(resignObserver)
    }
    #endif

    #if canImport(AppKit)
    private func setupAppKitObservers() {
        let center = NotificationCenter.default

        // App becoming active
        let activeObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleDidBecomeActive()
            }
        }
        observers.append(activeObserver)

        // App resigning active
        let resignObserver = center.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleWillResignActive()
            }
        }
        observers.append(resignObserver)

        // macOS doesn't have background/foreground like iOS
        // but we can track window focus changes if needed
    }
    #endif

    private func removeNotificationObservers() {
        #if canImport(UIKit) || canImport(AppKit)
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        #endif
    }

    // MARK: - Event Handlers

    private func handleDidEnterBackground() async {
        NDKLogger.log(.info, category: .connection, "📱 App entered background")
        await delegate?.connectionMonitorDidEnterBackground()
    }

    private func handleWillEnterForeground() async {
        NDKLogger.log(.info, category: .connection, "📱 App entering foreground")
        await delegate?.connectionMonitorDidEnterForeground()
    }

    private func handleDidBecomeActive() async {
        NDKLogger.log(.info, category: .connection, "📱 App became active")
        await delegate?.connectionMonitorDidBecomeActive()
    }

    private func handleWillResignActive() async {
        NDKLogger.log(.info, category: .connection, "📱 App will resign active")
        await delegate?.connectionMonitorWillResignActive()
    }

    deinit {
        Task { [observers] in
            #if canImport(UIKit) || canImport(AppKit)
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            #endif
        }
    }
}
