#!/usr/bin/env swift

import Foundation

// Simulate the key generation
var bytes = [UInt8](repeating: 0, count: 32)
for i in 0 ..< 32 {
    bytes[i] = UInt8.random(in: 0 ... 255)
}

let hexString = bytes.map { String(format: "%02x", $0) }.joined()

print("Generated key: \(hexString)")
print("Length: \(hexString.count)")
print("Expected: 64 characters")
print("Is 64 chars: \(hexString.count == 64)")

// Test data conversion
let data = Data(bytes)
print("Data count: \(data.count)")
print("Expected: 32 bytes")
print("Is 32 bytes: \(data.count == 32)")

// Test hex string to data conversion
if let dataFromHex = Data(hexString: hexString) {
    print("Hex->Data count: \(dataFromHex.count)")
    print("Hex->Data is 32 bytes: \(dataFromHex.count == 32)")
} else {
    print("Failed to convert hex string to data")
}
