import Foundation

/// Centralized date formatters for performance optimization
/// Creating DateFormatter instances is expensive, so we reuse them
public enum DateFormatters {

    // MARK: - Standard Formatters

    /// ISO8601 formatter for timestamps
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is safe here because:
    /// - Formatter is created once during lazy initialization
    /// - Never modified after creation (immutable usage pattern)
    /// - ISO8601DateFormatter is safe for concurrent reads
    public nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 formatter without fractional seconds
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is safe here because:
    /// - Formatter is created once during lazy initialization
    /// - Never modified after creation (immutable usage pattern)
    /// - ISO8601DateFormatter is safe for concurrent reads
    public nonisolated(unsafe) static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Standard date formatter for display
    public static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Date-only formatter
    public static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Time-only formatter
    public static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Custom Formatters

    /// Create a custom formatter with the given format
    /// Note: This creates a new formatter each time, use sparingly
    public static func custom(format: String, locale: Locale = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = locale
        return formatter
    }

    // MARK: - Relative Date Formatting

    /// Relative date formatter (e.g., "2 hours ago", "yesterday")
    public static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Short relative date formatter (e.g., "2h ago", "1d ago")
    public static let relativeShort: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Convenience Methods

    /// Format a Unix timestamp to ISO8601 string
    public static func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return iso8601.string(from: date)
    }

    /// Format a Unix timestamp for display
    public static func formatTimestampForDisplay(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return display.string(from: date)
    }

    /// Format a Unix timestamp as relative time
    public static func formatTimestampRelative(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return relative.localizedString(for: date, relativeTo: Date())
    }
}