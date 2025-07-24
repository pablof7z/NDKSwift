import SwiftUI
import Foundation
import NDKSwift

// MARK: - Helper Functions

/// Determines if the relative time display should update based on interval changes
private func shouldUpdateDisplay(oldInterval: TimeInterval, newInterval: TimeInterval) -> Bool {
    if oldInterval < TimeConstants.minute && newInterval < TimeConstants.minute {
        // Update every second for under 1 minute
        return true
    } else if oldInterval < TimeConstants.hour && newInterval < TimeConstants.hour {
        // Update when minute changes for under 1 hour
        return Int(oldInterval / TimeConstants.minute) != Int(newInterval / TimeConstants.minute)
    } else if oldInterval < TimeConstants.day && newInterval < TimeConstants.day {
        // Update when hour changes for under 1 day
        return Int(oldInterval / TimeConstants.hour) != Int(newInterval / TimeConstants.hour)
    } else {
        // Update when day changes for older times
        return Int(oldInterval / TimeConstants.day) != Int(newInterval / TimeConstants.day)
    }
}

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
                
                if shouldUpdateDisplay(oldInterval: oldInterval, newInterval: newInterval) {
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
        if interval < TimeConstants.minute {
            return "\(Int(interval))s"
        }
        
        // Less than 1 hour
        if interval < TimeConstants.hour {
            let minutes = Int(interval / TimeConstants.minute)
            return minutes == 1 ? "1m" : "\(minutes)m"
        }
        
        // Less than 1 day
        if interval < TimeConstants.day {
            let hours = Int(interval / TimeConstants.hour)
            return hours == 1 ? "1h" : "\(hours)h"
        }
        
        // Less than 1 week
        if interval < TimeConstants.week {
            let days = Int(interval / TimeConstants.day)
            return days == 1 ? "1d" : "\(days)d"
        }
        
        // Less than 1 month (approximately)
        if interval < TimeConstants.month {
            let weeks = Int(interval / TimeConstants.week)
            return weeks == 1 ? "1w" : "\(weeks)w"
        }
        
        // Less than 1 year
        if interval < TimeConstants.year {
            let months = Int(interval / TimeConstants.month)
            return months == 1 ? "1mo" : "\(months)mo"
        }
        
        // 1 year or more
        let years = Int(interval / TimeConstants.year)
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
                
                if shouldUpdateDisplay(oldInterval: oldInterval, newInterval: newInterval) {
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
        
        if interval < TimeConstants.minute {
            return "\(Int(interval)) seconds ago"
        }
        
        if interval < 2 * TimeConstants.minute {
            return "1 minute ago"
        }
        
        if interval < TimeConstants.hour {
            let minutes = Int(interval / TimeConstants.minute)
            return "\(minutes) minutes ago"
        }
        
        if interval < 2 * TimeConstants.hour {
            return "1 hour ago"
        }
        
        if interval < TimeConstants.day {
            let hours = Int(interval / TimeConstants.hour)
            return "\(hours) hours ago"
        }
        
        if interval < 2 * TimeConstants.day {
            return "1 day ago"
        }
        
        if interval < TimeConstants.month {
            let days = Int(interval / TimeConstants.day)
            return "\(days) days ago"
        }
        
        if interval < 2 * TimeConstants.month {
            return "1 month ago"
        }
        
        if interval < TimeConstants.year {
            let months = Int(interval / TimeConstants.month)
            return "\(months) months ago"
        }
        
        let years = Int(interval / TimeConstants.year)
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }
}

// MARK: - Preview

#if DEBUG
struct NDKRelativeTime_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 8) {
            NDKRelativeTime(date: Date().addingTimeInterval(-30))
            NDKRelativeTime(date: Date().addingTimeInterval(-5 * TimeConstants.minute))
            NDKRelativeTime(date: Date().addingTimeInterval(-TimeConstants.hour))
            NDKRelativeTime(date: Date().addingTimeInterval(-TimeConstants.day))
            
            Divider()
            
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-30))
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-5 * TimeConstants.minute))
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-TimeConstants.hour))
            NDKRelativeTimeLong(date: Date().addingTimeInterval(-TimeConstants.day))
        }
        .padding()
    }
}
#endif