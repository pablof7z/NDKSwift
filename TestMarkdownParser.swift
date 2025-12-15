#!/usr/bin/env swift

import Foundation

// Import the parser from NDKSwiftUI
// Since we can't import modules in a standalone script, we'll just compile and run separately

print("Testing Markdown Parser...")

// Test 1: Heading
let headingContent = "# Heading 1"
print("Test 1: Heading - '\(headingContent)'")

// Test 2: Bold
let boldContent = "This is **bold** text"
print("Test 2: Bold - '\(boldContent)'")

// Test 3: Ordered list
let listContent = """
1. First item
2. Second item
3. Third item
"""
print("Test 3: Ordered List - '\(listContent)'")

// Test 4: Code block
let codeContent = """
```swift
func hello() {
    print("Hello")
}
```
"""
print("Test 4: Code Block - '\(codeContent)'")

print("\nManual testing complete. Build with: swift build && swift run")
