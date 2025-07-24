import SwiftUI
import NDKSwift

// MARK: - Centralized Formatting Utilities
// Following DRY principle: All formatting logic consolidated in one place

// MARK: - Pubkey Formatting

struct PubkeyFormatter {
    /// Format a pubkey to show first 8 characters with ellipsis
    static func formatShort(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
    
    /// Format a pubkey to show first 8 characters only
    static func formatCompact(_ pubkey: String) -> String {
        String(pubkey.prefix(8))
    }
    
    /// Format a pubkey for avatar display (first character uppercase)
    static func formatForAvatar(_ pubkey: String) -> String {
        String(pubkey.prefix(1)).uppercased()
    }
    
    /// Format a pubkey with custom length
    static func format(_ pubkey: String, length: Int) -> String {
        guard pubkey.count > length else { return pubkey }
        return String(pubkey.prefix(length)) + "..."
    }
    
    /// Format for display name with fallback options
    static func displayName(from profile: NDKUserProfile?, pubkey: String) -> String {
        if let displayName = profile?.displayName, !displayName.isEmpty {
            return displayName
        } else if let name = profile?.name, !name.isEmpty {
            return name
        } else {
            return formatShort(pubkey)
        }
    }
}

// MARK: - Time Formatting

struct RelativeTimeFormatter {
    /// Standard relative time formatting
    static func relativeTime(from timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Relative time from Date
    static func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Short relative time formatting
    static func shortRelativeTime(from timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Ultra-compact time formatting for cards
    static func compactTime(from timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            return "\(Int(timeInterval / 60))m"
        } else if timeInterval < 86400 {
            return "\(Int(timeInterval / 3600))h"
        } else if timeInterval < 604800 {
            return "\(Int(timeInterval / 86400))d"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Content Formatting

struct ContentFormatter {
    /// Smart truncation of content based on context
    static func smartTruncate(_ content: String, maxLength: Int, context: TruncationContext = .general) -> String {
        guard content.count > maxLength else { return content }
        
        let actualLimit = max(maxLength - 3, 10) // Reserve space for ellipsis
        let truncated = String(content.prefix(actualLimit))
        
        // Try to break at word boundary for better readability
        if let lastSpace = truncated.lastIndex(of: " "), lastSpace > truncated.startIndex {
            let wordBoundaryTruncated = String(truncated[..<lastSpace])
            if wordBoundaryTruncated.count > actualLimit * 3 / 4 { // Only use word boundary if it's not too short
                return wordBoundaryTruncated + "..."
            }
        }
        
        return truncated + "..."
    }
    
    /// Format highlight content with proper quotes
    static func formatHighlight(_ content: String, addQuotes: Bool = true) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return addQuotes ? "\"\(trimmed)\"" : trimmed
    }
    
    /// Extract domain from URL for display
    static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "Source" }
        return url.host ?? "Source"
    }
    
    /// Format sats amount with appropriate units
    static func formatSatsAmount(_ sats: Int64) -> String {
        if sats < 1000 {
            return "\(sats)"
        } else if sats < 1_000_000 {
            let k = Double(sats) / 1000.0
            return String(format: "%.1fk", k)
        } else {
            let m = Double(sats) / 1_000_000.0
            return String(format: "%.1fM", m)
        }
    }
}

// MARK: - Supporting Types

enum TruncationContext {
    case general
    case quote
    case title
    case description
    
    var preferredLength: Int {
        switch self {
        case .general: return 100
        case .quote: return 150
        case .title: return 50
        case .description: return 200
        }
    }
}

// MARK: - Validation Utilities

struct ValidationUtilities {
    /// Validate if a string is a valid Nostr private key (nsec)
    static func isValidNsec(_ nsec: String) -> Bool {
        return nsec.hasPrefix("nsec") && nsec.count > 10
    }
    
    /// Validate if a string is a valid URL
    static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    /// Clean and validate highlight content
    static func cleanHighlightContent(_ content: String) -> String? {
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty && cleaned.count >= 3 else { return nil }
        return cleaned
    }
}

// MARK: - SwiftUI Integration Helpers

extension View {
    /// Apply smart content truncation with consistent styling
    func smartContent(_ content: String, maxLength: Int = 100, context: TruncationContext = .general) -> some View {
        Text(ContentFormatter.smartTruncate(content, maxLength: maxLength, context: context))
    }
    
    /// Display relative time with consistent formatting
    func relativeTime(from timestamp: Timestamp, style: RelativeTimeStyle = .standard) -> some View {
        let timeString: String
        switch style {
        case .standard:
            timeString = RelativeTimeFormatter.relativeTime(from: timestamp)
        case .short:
            timeString = RelativeTimeFormatter.shortRelativeTime(from: timestamp)
        case .compact:
            timeString = RelativeTimeFormatter.compactTime(from: timestamp)
        }
        return Text(timeString)
    }
}

enum RelativeTimeStyle {
    case standard
    case short
    case compact
}