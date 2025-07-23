import SwiftUI
import Foundation
import NDKSwift

// MARK: - NDKRelativeTime

/// A SwiftUI view that displays relative time (e.g., "2 minutes ago", "1 hour ago")
/// with automatic updates and smart refresh intervals.
///
/// The component automatically updates at appropriate intervals:
/// - Every second for times under 1 minute
/// - Every minute for times under 1 hour  
/// - Every hour for times under 1 day
/// - Every day for older times
///
/// ## Usage
///
/// ```swift
/// // With NDKEvent
/// NDKRelativeTime(event: event)
///
/// // With Date
/// NDKRelativeTime(date: date)
///
/// // With timestamp
/// NDKRelativeTime(timestamp: 1640995200)
/// ```
public struct NDKRelativeTime: View {
    
    // MARK: - Properties
    
    private let date: Date
    @State private var currentTime = Date()
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // MARK: - Initialization
    
    /// Initialize with an NDKEvent
    public init(event: NDKEvent) {
        self.date = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
    }
    
    /// Initialize with a Date
    public init(date: Date) {
        self.date = date
    }
    
    /// Initialize with a Unix timestamp
    public init(timestamp: Timestamp) {
        self.date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    // MARK: - Body
    
    public var body: some View {
        Text(relativeTimeString)
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in
                let newTime = Date()
                let oldInterval = currentTime.timeIntervalSince(date)
                let newInterval = newTime.timeIntervalSince(date)
                
                // Only update when the display value would actually change
                let shouldUpdate: Bool
                if oldInterval < 60 && newInterval < 60 {
                    // Update every second for under 1 minute
                    shouldUpdate = true
                } else if oldInterval < 3600 && newInterval < 3600 {
                    // Update when minute changes for under 1 hour
                    shouldUpdate = Int(oldInterval / 60) != Int(newInterval / 60)
                } else if oldInterval < 86400 && newInterval < 86400 {
                    // Update when hour changes for under 1 day
                    shouldUpdate = Int(oldInterval / 3600) != Int(newInterval / 3600)
                } else {
                    // Update when day changes for older times
                    shouldUpdate = Int(oldInterval / 86400) != Int(newInterval / 86400)
                }
                
                if shouldUpdate {
                    currentTime = newTime
                }
            }
            .onAppear {
                currentTime = Date()
            }
    }
    
    // MARK: - Private Methods
    
    private var relativeTimeString: String {
        let interval = currentTime.timeIntervalSince(date)
        
        // Handle future dates
        if interval < 0 {
            return "in the future"
        }
        
        // Less than 30 seconds
        if interval < 30 {
            return "just now"
        }
        
        // Less than 1 minute
        if interval < 60 {
            return "\(Int(interval))s"
        }
        
        // Less than 1 hour
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return minutes == 1 ? "1m" : "\(minutes)m"
        }
        
        // Less than 1 day
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1h" : "\(hours)h"
        }
        
        // Less than 1 week
        if interval < 604800 {
            let days = Int(interval / 86400)
            return days == 1 ? "1d" : "\(days)d"
        }
        
        // Less than 1 month (approximately)
        if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return weeks == 1 ? "1w" : "\(weeks)w"
        }
        
        // Less than 1 year
        if interval < 31536000 {
            let months = Int(interval / 2592000)
            return months == 1 ? "1mo" : "\(months)mo"
        }
        
        // 1 year or more
        let years = Int(interval / 31536000)
        return years == 1 ? "1y" : "\(years)y"
    }
}

// MARK: - NDKRelativeTimeLong

/// A variant that shows longer form relative time descriptions
/// (e.g., "2 minutes ago" instead of "2m")
public struct NDKRelativeTimeLong: View {
    
    private let date: Date
    @State private var currentTime = Date()
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // MARK: - Initialization
    
    /// Initialize with an NDKEvent
    public init(event: NDKEvent) {
        self.date = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
    }
    
    /// Initialize with a Date
    public init(date: Date) {
        self.date = date
    }
    
    /// Initialize with a Unix timestamp
    public init(timestamp: Timestamp) {
        self.date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    // MARK: - Body
    
    public var body: some View {
        Text(longRelativeTimeString)
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in
                let newTime = Date()
                let oldInterval = currentTime.timeIntervalSince(date)
                let newInterval = newTime.timeIntervalSince(date)
                
                let shouldUpdate: Bool
                if oldInterval < 60 && newInterval < 60 {
                    shouldUpdate = true
                } else if oldInterval < 3600 && newInterval < 3600 {
                    shouldUpdate = Int(oldInterval / 60) != Int(newInterval / 60)
                } else if oldInterval < 86400 && newInterval < 86400 {
                    shouldUpdate = Int(oldInterval / 3600) != Int(newInterval / 3600)
                } else {
                    shouldUpdate = Int(oldInterval / 86400) != Int(newInterval / 86400)
                }
                
                if shouldUpdate {
                    currentTime = newTime
                }
            }
            .onAppear {
                currentTime = Date()
            }
    }
    
    // MARK: - Private Methods
    
    private var longRelativeTimeString: String {
        let interval = currentTime.timeIntervalSince(date)
        
        if interval < 0 {
            return "in the future"
        }
        
        if interval < 30 {
            return "just now"
        }
        
        if interval < 60 {
            return "\(Int(interval)) seconds ago"
        }
        
        if interval < 120 {
            return "1 minute ago"
        }
        
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minutes ago"
        }
        
        if interval < 7200 {
            return "1 hour ago"
        }
        
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hours ago"
        }
        
        if interval < 172800 {
            return "1 day ago"
        }
        
        if interval < 2592000 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        }
        
        if interval < 5184000 {
            return "1 month ago"
        }
        
        if interval < 31536000 {
            let months = Int(interval / 2592000)
            return "\(months) months ago"
        }
        
        let years = Int(interval / 31536000)
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }
}

// MARK: - Preview

#if DEBUG
struct NDKRelativeTime_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 8) {
            NDKRelativeTime(date: Date().addingTimeInterval(-30))
            NDKRelativeTime(date: Date().addingTimeInterval(-300))
            NDKRelativeTime(date: Date().addingTimeInterval(-3600))
            NDKRelativeTime(date: Date().addingTimeInterval(-86400))
            
            Divider()
            
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-30))
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-300))
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-3600))
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-86400))
        }
        .padding()
    }
}
#endif