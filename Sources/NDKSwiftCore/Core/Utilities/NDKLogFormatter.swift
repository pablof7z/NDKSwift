import Foundation

/// Formatting utilities for NDK logging
public enum NDKLogFormatter {
    /// Truncate large arrays in messages for logging
    public static func truncateMessage(_ message: String) -> String {
        guard let data = message.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
              jsonArray.count >= 2
        else {
            return message
        }

        // Handle REQ messages specially
        if let msgType = jsonArray[0] as? String, msgType == "REQ" {
            var result = "[\"REQ\""

            // Add subscription ID
            if jsonArray.count > 1, let subId = jsonArray[1] as? String {
                result += ",\"\(subId)\""
            }

            // Process filters
            for i in 2 ..< jsonArray.count {
                if let filter = jsonArray[i] as? [String: Any] {
                    result += ","
                    result += truncateFilter(filter)
                }
            }

            result += "]"
            return result
        }

        // For other messages, return as-is
        return message
    }

    /// Truncate large arrays in filters
    private static func truncateFilter(_ filter: [String: Any]) -> String {
        var truncatedFilter: [String: Any] = [:]

        for (key, value) in filter {
            if let array = value as? [Any], array.count > 100 {
                // Replace large arrays with summary
                truncatedFilter[key] = "<\(array.count)-\(key)>"
            } else {
                truncatedFilter[key] = value
            }
        }

        // Convert back to JSON string
        if let data = try? JSONSerialization.data(withJSONObject: truncatedFilter, options: [.sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        return "{}"
    }

    /// Get emoji for log category
    public static func emojiForCategory(_ category: NDKLogCategory) -> String {
        switch category {
        case .network: return "📡"
        case .relay: return "🔗"
        case .subscription: return "🔍"
        case .event: return "📝"
        case .cache: return "💾"
        case .auth: return "🔐"
        case .wallet: return "💰"
        case .general: return "ℹ️"
        case .connection: return "🔌"
        case .outbox: return "🎯"
        case .signer: return "✍️"
        case .sync: return "🔄"
        case .performance: return "⚡"
        case .security: return "🛡️"
        case .database: return "🗄️"
        case .signature: return "🔏"
        }
    }
}
