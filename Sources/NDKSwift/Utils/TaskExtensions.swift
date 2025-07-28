import Foundation

/// Extensions to simplify common Task patterns in the codebase
extension Task where Success == Void, Failure == Never {
    /// Creates a Task with weak self capture, automatically handling nil self
    /// 
    /// Example:
    /// ```swift
    /// // Before:
    /// Task { [weak self] in
    ///     guard let self = self else { return }
    ///     await self.doSomething()
    /// }
    /// 
    /// // After:
    /// Task.weak(self) { strongSelf in
    ///     await strongSelf.doSomething()
    /// }
    /// ```
    @discardableResult
    static func weak<T: AnyObject>(_ object: T, operation: @escaping (T) async -> Void) -> Task<Void, Never> {
        Task { [weak object] in
            guard let object = object else { return }
            await operation(object)
        }
    }
    
    /// Creates a detached Task with weak self capture
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// Task.detached { [weak self] in
    ///     guard let self = self else { return }
    ///     await self.doSomething()
    /// }
    /// 
    /// // After:
    /// Task.detachedWeak(self) { strongSelf in
    ///     await strongSelf.doSomething()
    /// }
    /// ```
    @discardableResult
    static func detachedWeak<T: AnyObject>(_ object: T, operation: @escaping (T) async -> Void) -> Task<Void, Never> {
        Task.detached { [weak object] in
            guard let object = object else { return }
            await operation(object)
        }
    }
}

/// Extensions for Tasks with return values
extension Task {
    /// Creates a Task with weak self capture that returns a value
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// Task { [weak self] in
    ///     guard let self = self else { return nil }
    ///     return await self.fetchData()
    /// }
    /// 
    /// // After:
    /// Task.weak(self) { strongSelf in
    ///     return await strongSelf.fetchData()
    /// }
    /// ```
    static func weak<T: AnyObject, R>(_ object: T, operation: @escaping (T) async throws -> R) -> Task<R?, Failure> where Success == R?, Failure == Error {
        Task { [weak object] in
            guard let object = object else { return nil }
            return try await operation(object)
        }
    }
}