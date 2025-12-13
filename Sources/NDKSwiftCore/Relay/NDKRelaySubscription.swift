import Foundation

/// Represents the delay type for groupable subscriptions
public enum NDKSubscriptionDelayType: Sendable {
    case atLeast // Wait at least this long before executing
    case atMost // Execute within this time at most
}

/// Status of a relay subscription group
enum NDKRelaySubscriptionStatus: Int, Comparable {
    case initial = 0
    case pending = 1
    case waiting = 2
    case running = 3
    case closed = 4

    static func < (lhs: NDKRelaySubscriptionStatus, rhs: NDKRelaySubscriptionStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Groups together a number of subscriptions to be executed within a single specific relay
actor NDKRelaySubscription {
    let fingerprint: String
    let relay: NDKRelay
    let isGroupable: Bool

    private var items: [(subscription: NDKSubscriptionCoordinator, filters: [NDKFilter])] = []
    private var status: NDKRelaySubscriptionStatus = .initial
    private var executionTask: Task<Void, Never>?
    private var fireTime: Date?
    private var delayType: NDKSubscriptionDelayType?
    private var eosed = false

    /// The subscription ID used for this group's REQ
    var subId: String?

    init(relay: NDKRelay, fingerprint: String, isGroupable: Bool) {
        self.relay = relay
        self.fingerprint = fingerprint
        self.isGroupable = isGroupable
    }

    /// Adds a subscription and its filters to this group
    func addItem(_ subscription: NDKSubscriptionCoordinator, filters: [NDKFilter]) {
        items.append((subscription, filters))

        NDKLogger.log(.debug, category: .subscription,
                      "📎 Added subscription to group \(fingerprint) (now \(items.count) items)")
    }

    /// Removes a subscription from this group
    func removeItem(_ subscription: NDKSubscriptionCoordinator) -> Bool {
        let initialCount = items.count
        items.removeAll { $0.subscription === subscription }
        return items.count < initialCount
    }

    /// Checks if this group can accept new items
    func canAcceptNewItems() -> Bool {
        status < .running
    }

    /// Checks if this group is empty
    func isEmpty() -> Bool {
        items.isEmpty
    }

    /// Checks if this group is active
    func isActive() -> Bool {
        status == .running
    }

    /// Schedules execution with a delay
    func scheduleExecution(delay: TimeInterval, delayType: NDKSubscriptionDelayType) {
        // If we already have a timer, we might need to adjust it
        if let existingFireTime = fireTime,
           let existingDelayType = self.delayType
        {
            let timeUntilFire = existingFireTime.timeIntervalSinceNow

            switch (existingDelayType, delayType) {
            case (.atLeast, .atLeast):
                // Extend timeout to the larger one
                if timeUntilFire < delay {
                    reschedule(delay: delay, delayType: delayType)
                }
            case (.atLeast, .atMost), (.atMost, .atMost):
                // Reduce timeout to the smaller one
                if timeUntilFire > delay {
                    reschedule(delay: delay, delayType: delayType)
                }
            case (.atMost, .atLeast):
                // Keep the at-most constraint if fire time is within the at-least delay
                if timeUntilFire > delay {
                    reschedule(delay: delay, delayType: delayType)
                }
            }
        } else {
            // First scheduling
            reschedule(delay: delay, delayType: delayType)
        }
    }

    private func reschedule(delay: TimeInterval, delayType: NDKSubscriptionDelayType) {
        // Cancel existing timer
        executionTask?.cancel()

        status = .pending
        fireTime = Date().addingTimeInterval(delay)
        self.delayType = delayType

        let startTime = Date()
        executionTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                // Record delay metrics
                let actualDelay = Date().timeIntervalSince(startTime)
                await NDKSubscriptionMetrics.recordDelay(
                    actualDelay: actualDelay,
                    configuredDelay: delay,
                    delayType: delayType
                )
                await execute()
            }
        }
    }

    /// Cancels pending execution
    func cancelPendingExecution() {
        executionTask?.cancel()
        executionTask = nil
    }

    /// Executes the grouped subscription
    func execute() async {
        guard await relay.isConnected else {
            status = .waiting
            NDKLogger.log(.debug, category: .subscription,
                          "⏳ Relay \(relay.url) not connected, waiting for group \(fingerprint)")
            return
        }

        status = .running

        // Compile filters
        let compiledFilters = compileFilters()

        // Generate subscription ID if we don't have one yet (reuse existing on reconnection)
        if subId == nil {
            subId = NDKSubscriptionIDGenerator.generateRelayID(
                from: fingerprint,
                suffix: String(UUID().uuidString.prefix(8))
            )
        }

        guard let subId = subId else { return }

        NDKLogger.log(.debug, category: .subscription,
                      "🚀 Executing group \(fingerprint) with \(compiledFilters.count) filters on \(relay.url)")
        NDKLogger.log(.debug, category: .subscription,
                      "🆔 [SubGroup] Generated subscription ID '\(subId)' for group '\(fingerprint)'")

        // IMPORTANT: Track subscription ID mapping BEFORE sending REQ to avoid race condition
        // where events arrive before the mapping is established
        NDKLogger.log(.debug, category: .subscription,
                      "📌 [SubGroup] Requesting manager to track subscription ID '\(subId)' for group '\(fingerprint)'")
        await relay.subscriptionManager.trackGroupSubscriptionId(self)

        // Record REQ message metrics
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: items.count, relay: relay.url)

        // Send REQ to relay (after tracking is set up)
        await relay.sendSubscription(id: subId, filters: compiledFilters)

        // Track this subscription on the relay
        await relay.trackSubscription(self)

        // CRITICAL: Register the relay-specific subscription ID with NDKSubscriptionCoordinatorManager
        // This allows events arriving with the relay-generated ID to be routed to the correct subscriptions
        if let ndk = relay.ndk {
            NDKLogger.log(.debug, category: .subscription,
                          "🔗 [SubGroup] Registering relay ID '\(subId)' → fingerprint '\(fingerprint)' with NDKSubscriptionCoordinatorManager")
            await ndk.internalSubscriptionManager.registerRelayIdMapping(relayId: subId, fingerprint: fingerprint)
        } else {
            NDKLogger.log(.warning, category: .subscription,
                          "⚠️ [SubGroup] Cannot register relay ID mapping - no NDK reference")
        }
    }

    /// Compiles all filters from grouped items
    func compileFilters() -> [NDKFilter] {
        // Separate filters with limits from those without
        var filtersWithLimits: [NDKFilter] = []
        var filtersToMerge: [[NDKFilter]] = []

        // Group filters by their position across all items
        let maxFilterCount = items.map { $0.filters.count }.max() ?? 0

        for filterIndex in 0 ..< maxFilterCount {
            var filtersAtIndex: [NDKFilter] = []

            for item in items {
                if filterIndex < item.filters.count {
                    let filter = item.filters[filterIndex]
                    if filter.limit != nil {
                        filtersWithLimits.append(filter)
                    } else {
                        filtersAtIndex.append(filter)
                    }
                }
            }

            if !filtersAtIndex.isEmpty {
                filtersToMerge.append(filtersAtIndex)
            }
        }

        // Merge filters without limits
        var mergedFilters: [NDKFilter] = []
        for filtersGroup in filtersToMerge {
            mergedFilters.append(contentsOf: NDKFilterGrouping.mergeFilters(filtersGroup))
        }

        // Concatenate filters with limits
        return mergedFilters + filtersWithLimits
    }

    /// Handles incoming event from relay
    func handleEvent(_ event: NDKEvent, from relay: NDKRelay) async {
        // Dispatch to all subscriptions in this group
        for item in items {
            await item.subscription.handleEvent(event, from: relay)
        }
    }

    /// Handles EOSE from relay
    func handleEOSE(subscriptionId: String) async {
        guard subscriptionId == subId else {
            // This is for an old subscription we abandoned
            NDKLogger.log(.debug, category: .subscription,
                          "🔚 Received EOSE for abandoned subscription \(subscriptionId)")
            await relay.closeSubscription(id: subscriptionId)
            return
        }

        eosed = true

        // Notify all subscriptions in this group
        for item in items {
            await item.subscription.handleEOSE(from: relay)
        }

        // If all subscriptions want to close on EOSE, close this group
        let allCloseOnEose = items.allSatisfy { $0.subscription.closeOnEose }
        if allCloseOnEose {
            await close()
        }
    }

    /// Handles CLOSED from relay
    func handleClosed(subscriptionId: String, message: String) async {
        guard subscriptionId == subId else { return }

        NDKLogger.log(.warning, category: .subscription,
                      "🚫 Relay closed subscription \(subscriptionId): \(message)")

        // Notify all subscriptions
        for item in items {
            await item.subscription.handleClosed(from: relay, message: message)
        }

        await close()
    }

    /// Closes this group
    func close() async {
        NDKLogger.log(.debug, category: .subscription,
                      "🔒 [SubGroup] Closing group '\(fingerprint)' with subscription ID '\(subId ?? "none")'")

        status = .closed
        executionTask?.cancel()

        if let subId = subId {
            await relay.closeSubscription(id: subId)

            // Clean up relay ID mapping from NDKSubscriptionCoordinatorManager
            if relay.ndk != nil {
                // Note: We would need to add a method to remove the mapping
                // For now, the mapping will be cleaned up when the subscription is removed
                NDKLogger.log(.debug, category: .subscription,
                              "🗑️ [SubGroup] Relay ID mapping for '\(subId)' will be cleaned up with subscription")
            }
        }

        // Notify manager
        await relay.subscriptionManager.onGroupClosed(self)
    }
}

// MARK: - Testing Support

extension NDKRelaySubscription {
    /// Get subscription IDs for testing
    func getSubscriptionIds() async -> [String] {
        items.map { $0.subscription.id }
    }

    /// Force immediate execution for testing
    func executeNow() async {
        guard status < .running else { return }
        executionTask?.cancel()
        await execute()
    }

    /// Check if this group is active
    func isActive() async -> Bool {
        status < .closed
    }

    #if DEBUG
        /// Get detailed inspection data for testing
        func inspectForTesting() async -> NDKRelaySubscriptionManager.GroupInspectionData {
            NDKRelaySubscriptionManager.GroupInspectionData(
                fingerprint: fingerprint,
                isGroupable: isGroupable,
                itemCount: items.count,
                status: String(describing: status),
                subId: subId
            )
        }
    #endif
}
