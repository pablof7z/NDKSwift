import Foundation

/// Thread-safe wrapper for atomic value access
@propertyWrapper
public final class AtomicValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    
    public init(_ initialValue: T) {
        self._value = initialValue
    }
    
    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
    
    public var wrappedValue: T {
        get { value }
        set { value = newValue }
    }
}