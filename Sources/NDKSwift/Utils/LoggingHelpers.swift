import Foundation

/// Helper utilities for consistent logging patterns across NDKSwift
public enum LoggingHelpers {
    
    /// Formats a method entry log message with consistent formatting
    /// - Parameters:
    ///   - className: The name of the class/actor
    ///   - methodName: The name of the method being entered
    ///   - parameters: Optional dictionary of parameter names and values
    /// - Returns: A consistently formatted log message
    public static func methodEntry(
        _ className: String,
        _ methodName: String,
        parameters: [String: Any]? = nil
    ) -> String {
        var message = "\(className).\(methodName)"
        
        if let parameters = parameters, !parameters.isEmpty {
            let params = parameters
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            message += " - \(params)"
        }
        
        return message
    }
    
    /// Formats a method result log message with consistent formatting
    /// - Parameters:
    ///   - className: The name of the class/actor
    ///   - methodName: The name of the method
    ///   - result: Description of the result
    /// - Returns: A consistently formatted log message
    public static func methodResult(
        _ className: String,
        _ methodName: String,
        result: String
    ) -> String {
        return "\(className).\(methodName) - Result: \(result)"
    }
    
    /// Formats a state change log message
    /// - Parameters:
    ///   - className: The name of the class/actor
    ///   - property: The property that changed
    ///   - from: Previous value
    ///   - to: New value
    /// - Returns: A consistently formatted log message
    public static func stateChange(
        _ className: String,
        property: String,
        from: Any,
        to: Any
    ) -> String {
        return "\(className).\(property) - Changed from \(from) to \(to)"
    }
    
    /// Formats an error log message
    /// - Parameters:
    ///   - className: The name of the class/actor
    ///   - methodName: The name of the method where error occurred
    ///   - error: The error that occurred
    ///   - context: Additional context about the error
    /// - Returns: A consistently formatted log message
    public static func error(
        _ className: String,
        _ methodName: String,
        error: Error,
        context: String? = nil
    ) -> String {
        var message = "\(className).\(methodName) - Error: \(error)"
        if let context = context {
            message += " (Context: \(context))"
        }
        return message
    }
    
    /// Formats a warning log message
    /// - Parameters:
    ///   - className: The name of the class/actor
    ///   - methodName: The name of the method
    ///   - warning: The warning message
    /// - Returns: A consistently formatted log message
    public static func warning(
        _ className: String,
        _ methodName: String,
        warning: String
    ) -> String {
        return "\(className).\(methodName) - Warning: \(warning)"
    }
    
    /// Formats a collection summary for logging
    /// - Parameters:
    ///   - items: The collection to summarize
    ///   - name: Name of the collection
    /// - Returns: A summary string
    public static func collectionSummary<T: Collection>(
        _ items: T,
        name: String
    ) -> String {
        return "\(name): \(items.count) items"
    }
    
    /// Formats timing information for performance logging
    /// - Parameters:
    ///   - className: The name of the class/actor
    ///   - methodName: The name of the method
    ///   - duration: Duration in seconds
    ///   - itemCount: Optional number of items processed
    /// - Returns: A consistently formatted log message
    public static func timing(
        _ className: String,
        _ methodName: String,
        duration: TimeInterval,
        itemCount: Int? = nil
    ) -> String {
        var message = "\(className).\(methodName) - Completed in \(String(format: "%.3f", duration))s"
        
        if let count = itemCount {
            let rate = Double(count) / duration
            message += " (\(count) items, \(String(format: "%.1f", rate)) items/s)"
        }
        
        return message
    }
}

// MARK: - Convenience Extensions

public extension NDKLogger {
    /// Log a method entry with consistent formatting
    static func logMethodEntry(
        _ level: NDKLogLevel = .trace,
        category: NDKLogCategory,
        className: String,
        methodName: String,
        parameters: [String: Any]? = nil
    ) {
        let message = LoggingHelpers.methodEntry(className, methodName, parameters: parameters)
        log(level, category: category, message)
    }
    
    /// Log a method result with consistent formatting
    static func logMethodResult(
        _ level: NDKLogLevel = .debug,
        category: NDKLogCategory,
        className: String,
        methodName: String,
        result: String
    ) {
        let message = LoggingHelpers.methodResult(className, methodName, result: result)
        log(level, category: category, message)
    }
    
    /// Log an error with consistent formatting
    static func logError(
        category: NDKLogCategory,
        className: String,
        methodName: String,
        error: Error,
        context: String? = nil
    ) {
        let message = LoggingHelpers.error(className, methodName, error: error, context: context)
        log(.error, category: category, message)
    }
    
    /// Log timing information with consistent formatting
    static func logTiming(
        category: NDKLogCategory,
        className: String,
        methodName: String,
        duration: TimeInterval,
        itemCount: Int? = nil
    ) {
        let message = LoggingHelpers.timing(className, methodName, duration: duration, itemCount: itemCount)
        log(.debug, category: category, message)
    }
}