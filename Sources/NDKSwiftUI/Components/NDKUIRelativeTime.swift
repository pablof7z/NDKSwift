import SwiftUI
import NDKSwift

/// Displays a timestamp in relative format (e.g., "2m ago", "1h ago", "Yesterday")
///
/// This component automatically updates the display as time passes,
/// providing a user-friendly representation of when an event occurred.
///
/// ## Usage
/// ```swift
/// NDKUIRelativeTime(timestamp: event.createdAt)
///     .font(.caption)
///     .foregroundStyle(.secondary)
/// ```
public struct NDKUIRelativeTime: View {
    private let timestamp: Timestamp
    private let updateInterval: TimeInterval
    
    @State private var currentTime = Date()
    @State private var timer: Timer?
    
    /// Initialize a relative time display
    /// - Parameters:
    ///   - timestamp: The Unix timestamp to display
    ///   - updateInterval: How often to update the display (default: 60 seconds)
    public init(timestamp: Timestamp, updateInterval: TimeInterval = 60) {
        self.timestamp = timestamp
        self.updateInterval = updateInterval
    }
    
    public var body: some View {
        Text(relativeTimeString)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
    }
    
    // MARK: - Private Properties
    
    private var relativeTimeString: String {
        let eventDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let elapsed = currentTime.timeIntervalSince(eventDate)
        
        // Future dates
        if elapsed < 0 {
            return "in the future"
        }
        
        // Less than a minute
        if elapsed < 60 {
            return "now"
        }
        
        // Less than an hour
        if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return minutes == 1 ? "1m" : "\(minutes)m"
        }
        
        // Less than a day
        if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return hours == 1 ? "1h" : "\(hours)h"
        }
        
        // Less than a week
        if elapsed < 604800 {
            let days = Int(elapsed / 86400)
            if days == 1 {
                return "Yesterday"
            }
            return "\(days)d"
        }
        
        // Less than a month (30 days)
        if elapsed < 2592000 {
            let weeks = Int(elapsed / 604800)
            return weeks == 1 ? "1w" : "\(weeks)w"
        }
        
        // Less than a year
        if elapsed < 31536000 {
            let months = Int(elapsed / 2592000)
            return months == 1 ? "1mo" : "\(months)mo"
        }
        
        // Years
        let years = Int(elapsed / 31536000)
        return years == 1 ? "1y" : "\(years)y"
    }
    
    // MARK: - Timer Management
    
    private func startTimer() {
        // Update immediately
        currentTime = Date()
        
        // Schedule periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Static Formatting Methods

public extension NDKUIRelativeTime {
    /// Format a timestamp as a relative time string without auto-updating
    /// - Parameter timestamp: The Unix timestamp to format
    /// - Returns: A relative time string (e.g., "2m", "1h", "Yesterday")
    static func format(_ timestamp: Timestamp) -> String {
        let eventDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let elapsed = Date().timeIntervalSince(eventDate)
        
        // Future dates
        if elapsed < 0 {
            return "in the future"
        }
        
        // Less than a minute
        if elapsed < 60 {
            return "now"
        }
        
        // Less than an hour
        if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return minutes == 1 ? "1m" : "\(minutes)m"
        }
        
        // Less than a day
        if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return hours == 1 ? "1h" : "\(hours)h"
        }
        
        // Less than a week
        if elapsed < 604800 {
            let days = Int(elapsed / 86400)
            if days == 1 {
                return "Yesterday"
            }
            return "\(days)d"
        }
        
        // Less than a month (30 days)
        if elapsed < 2592000 {
            let weeks = Int(elapsed / 604800)
            return weeks == 1 ? "1w" : "\(weeks)w"
        }
        
        // Less than a year
        if elapsed < 31536000 {
            let months = Int(elapsed / 2592000)
            return months == 1 ? "1mo" : "\(months)mo"
        }
        
        // Years
        let years = Int(elapsed / 31536000)
        return years == 1 ? "1y" : "\(years)y"
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIRelativeTime_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Current time
            NDKUIRelativeTime(timestamp: Date.currentNostrTimestamp)
            
            // 5 minutes ago
            NDKUIRelativeTime(timestamp: Date.currentNostrTimestamp - 300)
            
            // 2 hours ago
            NDKUIRelativeTime(timestamp: Date.currentNostrTimestamp - 7200)
            
            // Yesterday
            NDKUIRelativeTime(timestamp: Date.currentNostrTimestamp - 86400)
            
            // 1 week ago
            NDKUIRelativeTime(timestamp: Date.currentNostrTimestamp - 604800)
            
            // 2 months ago
            NDKUIRelativeTime(timestamp: Date.currentNostrTimestamp - 5184000)
        }
        .padding()
    }
}
#endif