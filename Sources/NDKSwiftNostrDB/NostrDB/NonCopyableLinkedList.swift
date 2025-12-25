import NDKSwiftCore

//
//  NonCopyableLinkedList.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-07-04.
//

/// A linked list to help with iteration of non-copyable elements
///
/// This is needed to provide an array-like abstraction or iterators since swift arrays or iterator protocols require the element to be "copyable"
struct NonCopyableLinkedList<T: ~Copyable>: ~Copyable {
    private var head: Node<T>?
    private var tail: Node<T>?
    private(set) var count: Int = 0

    /// Iterates over each item of the list, with enumeration support.
    func forEachItem<Y>(_ borrowingFunction: (_ index: Int, _ item: borrowing T) throws -> LoopCommand<Y>) rethrows -> Y? {
        var indexCounter = 0

        var cursor: Node? = head

        outerLoop: while let nextItem = cursor {
            let loopIterationResult = try borrowingFunction(indexCounter, nextItem.value)
            indexCounter += 1
            cursor = nextItem.next
            switch loopIterationResult {
            case .loopBreak:
                break outerLoop
            case .loopContinue:
                continue outerLoop
            case let .loopReturn(result):
                return result
            }
        }

        return nil
    }

    /// Iterates over each item of the list in reverse, with enumeration support.
    func forEachItemReversed<Y, E: Error>(_ borrowingFunction: (_ index: Int, _ item: borrowing T) throws(E) -> LoopCommand<Y>) throws(E) -> Y? {
        var indexCounter = count - 1
        var cursor: Node? = tail

        outerLoop: while let nextItem = cursor {
            let loopIterationResult = try borrowingFunction(indexCounter, nextItem.value)
            indexCounter -= 1
            cursor = nextItem.previous
            switch loopIterationResult {
            case .loopBreak:
                break outerLoop
            case .loopContinue:
                continue outerLoop
            case let .loopReturn(result):
                return result
            }
        }

        return nil
    }

    /// Iterates over each item of the list, with enumeration support, updating some value in each iteration and returning the final value at the end.
    func reduce<Y>(initialResult: Y, _ borrowingFunction: (_ index: Int, _ partialResult: Y, _ item: borrowing T) throws -> LoopCommand<Y>) throws -> Y {
        var indexCounter = 0
        var currentResult = initialResult

        var cursor: Node? = head

        outerLoop: while let nextItem = cursor {
            let loopIterationResult = try borrowingFunction(indexCounter, currentResult, nextItem.value)
            indexCounter += 1
            cursor = nextItem.next
            switch loopIterationResult {
            case .loopBreak:
                break outerLoop
            case .loopContinue:
                continue outerLoop
            case let .loopReturn(result):
                currentResult = result
                continue outerLoop
            }
        }

        return currentResult
    }

    /// Uses a specific item of the list based on a provided index.
    ///
    /// O(N/2) worst case scenario
    ///
    /// Returns `nil` if nothing was found
    func useItem<Y>(at index: Int, _ borrowingFunction: (_ item: borrowing T) throws -> Y) rethrows -> Y? {
        if index < 0 || index >= count {
            return nil
        } else if index < count / 2 {
            return try forEachItem { i, item in
                if i == index {
                    return try .loopReturn(borrowingFunction(item))
                }
                return .loopContinue
            }
        } else {
            return try forEachItemReversed { i, item in
                if i == index {
                    return try .loopReturn(borrowingFunction(item))
                }
                return .loopContinue
            }
        }
    }

    /// Adds an item to the tail end list
    mutating func add(item: consuming T) {
        guard head != nil, let currentTail = tail else {
            let firstNode = Node(value: item, next: nil, previous: nil)
            head = firstNode
            tail = firstNode
            count = 1
            return
        }
        let newTail = Node(value: item, next: nil, previous: currentTail)
        currentTail.next = newTail
        tail = newTail
        count += 1
    }

    /// A node of the linked list
    ///
    /// Should be `~Copyable` but that would require using a value type such as a struct or enum, and the Swift compiler does not support recursive enums with non-copyable objects for some reason. Example:
    /// ```swift
    /// enum List<Y: ~Copyable>: ~Copyable {
    ///     indirect case node(value: Y, next: NewList<Y>)  // <-- ERROR: Noncopyable enum 'List' cannot be marked indirect or have indirect cases yet
    ///     case empty
    /// }
    /// ```
    ///
    /// Therefore, we make it `private` to make sure we contain the exposure of this unsafe object to only this class. Outside users of the linked list can access objects via the iterator functions.
    private class Node<Item: ~Copyable> {
        let value: Item
        var next: Node?
        var previous: Node?

        init(value: consuming Item, next: consuming Node?, previous: consuming Node?) {
            self.value = value
            self.next = next
            self.previous = previous
        }
    }

    /// A loop command to allow closures to control the loop they are in.
    enum LoopCommand<Y> {
        /// Breaks out of the loop
        case loopBreak
        /// Continues to the next iteration of the loop
        case loopContinue
        /// Stops iterating and return a value
        case loopReturn(Y)
    }
}
