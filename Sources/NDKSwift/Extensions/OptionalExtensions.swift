import Foundation

extension Optional where Wrapped == String {
    /// Returns true if the string is nil or empty
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return value.isEmpty
        }
    }
    
    /// Returns the string value or an empty string if nil
    var orEmpty: String {
        self ?? ""
    }
}

extension Optional where Wrapped: Collection {
    /// Returns true if the collection is nil or empty
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return value.isEmpty
        }
    }
}