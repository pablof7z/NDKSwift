import Foundation
import NDKSwiftCore

// Test harness for Negentropy protocol conformance
// Compatible with hoytech/negentropy test suite

let frameSizeLimit = Int(ProcessInfo.processInfo.environment["FRAMESIZELIMIT"] ?? "0") ?? 0

let storage = NegentropyStorageVector()
var negentropy: Negentropy?

// Helper to print to stderr
var stderr = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data)
    }
}

// Helper for Data comparison
func compareData(_ a: Data, _ b: Data) -> Int {
    for i in 0 ..< min(a.count, b.count) {
        if a[i] < b[i] { return -1 }
        if a[i] > b[i] { return 1 }
    }
    if a.count < b.count { return -1 }
    if a.count > b.count { return 1 }
    return 0
}

// Using hex conversion from NDKSwift's DataExtensions

// Simple in-memory storage for testing
class NegentropyStorageVector: NegentropyStorage {
    private var items: [NegentropyItem] = []
    private var sealed = false

    func addItem(_ item: NegentropyItem) throws {
        guard !sealed else { throw NegentropyError.protocolError("already sealed") }
        items.append(item)
    }

    func seal() async throws {
        guard !sealed else { throw NegentropyError.protocolError("already sealed") }
        sealed = true

        // Sort items
        items.sort()

        // Check for duplicates
        for i in 1 ..< items.count {
            if items[i - 1] == items[i] {
                throw NegentropyError.protocolError("duplicate item")
            }
        }
    }

    func getItems(in range: NegentropyRange) async throws -> [NegentropyItem] {
        guard sealed else { throw NegentropyError.protocolError("not sealed") }

        return items.filter { item in
            // Check lower bound
            if let lower = range.lower {
                if item.timestamp < lower.timestamp { return false }
                if item.timestamp == lower.timestamp && compareData(item.id, lower.id) < 0 { return false }
            }

            // Check upper bound
            if let upper = range.upper {
                if item.timestamp > upper.timestamp { return false }
                if item.timestamp == upper.timestamp && compareData(item.id, upper.id) >= 0 { return false }
            }

            return true
        }
    }

    func getRangeInfo(_ range: NegentropyRange) async throws -> (fingerprint: Data, count: Int) {
        let items = try await getItems(in: range)
        let accumulator = NegentropyAccumulator.from(items)
        return (fingerprint: accumulator.fingerprint(), count: items.count)
    }

    func addItems(_: [NegentropyItem]) async throws {
        // Not needed for test harness
    }

    func removeItems(_: [Data]) async throws {
        // Not needed for test harness
    }
}

// Main command processing loop
while let line = readLine() {
    let parts = line.split(separator: ",")
    guard !parts.isEmpty else { continue }

    let command = String(parts[0])

    switch command {
    case "item":
        guard parts.count >= 3 else {
            print("Error: too few items", to: &stderr)
            exit(1)
        }
        let timestamp = UInt64(parts[1]) ?? 0
        let id = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idData = Data(hexString: id), idData.count == 32 else {
            print("Error: bad id format", to: &stderr)
            exit(1)
        }
        do {
            try storage.addItem(NegentropyItem(id: idData, timestamp: timestamp))
        } catch {
            print("Error adding item: \(error)", to: &stderr)
            exit(1)
        }

    case "seal":
        Task {
            do {
                try await storage.seal()
                negentropy = Negentropy(storage: storage, frameSizeLimit: frameSizeLimit)
            } catch {
                print("Error sealing: \(error)", to: &stderr)
                exit(1)
            }
        }

    case "initiate":
        Task {
            guard let negentropy = negentropy else {
                print("Error: not sealed", to: &stderr)
                exit(1)
            }
            do {
                let msg = try await negentropy.initiate()
                print("msg,\(msg.hexString)")
            } catch {
                print("Error initiating: \(error)", to: &stderr)
                exit(1)
            }
        }

    case "msg":
        guard parts.count >= 2 else {
            print("Error: missing message data", to: &stderr)
            exit(1)
        }
        let msgHex = String(parts[1])
        guard let msgData = Data(hexString: msgHex), msgData.count > 0 else {
            print("Error: bad message format", to: &stderr)
            exit(1)
        }

        Task {
            guard let negentropy = negentropy else {
                print("Error: not sealed", to: &stderr)
                exit(1)
            }
            do {
                let (responseData, haveIds, needIds) = try await negentropy.reconcile(msgData)

                for id in haveIds {
                    print("have,\(id)")
                }
                for id in needIds {
                    print("need,\(id)")
                }

                if let data = responseData {
                    print("msg,\(data.hexString)")
                } else {
                    print("done")
                }
            } catch {
                print("Error processing message: \(error)", to: &stderr)
                exit(1)
            }
        }

    default:
        print("Error: unknown command: \(command)", to: &stderr)
        exit(1)
    }
}

// Keep the run loop alive
RunLoop.main.run()
