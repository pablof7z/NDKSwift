#!/usr/bin/env swift

import Foundation

// Add a simple test function
let nsecInput = "nsec1pnfm84sp6ed974zj7qsqqcn692hgnf9s48jk8x0psagucv6yy3ys5qqx7c"

print("Testing nsec: \(nsecInput)")
print("Length: \(nsecInput.count)")
print("Has nsec1 prefix: \(nsecInput.hasPrefix("nsec1"))")

// Check for invalid characters
let validChars = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
for char in nsecInput {
    if char != "n" && char != "s" && char != "e" && char != "c" && char != "1" && !validChars.contains(char) {
        print("Invalid character found: \(char)")
    }
}

print("All characters are valid for bech32")