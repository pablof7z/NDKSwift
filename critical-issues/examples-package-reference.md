# Critical Issue: Examples Package References

## Problem
The Examples/Package.swift file contains incorrect package references that prevent the entire test suite from running properly.

## Details
- All targets in Examples/Package.swift reference `.product(name: "NDKSwift", package: "NDKSwift")`
- The actual package name is "NDKSwift-z94ws0" (as shown in the error messages)
- This causes build failures when running tests

## Impact
- Tests cannot be run with `swift test` from the root directory
- Examples cannot be built properly
- This blocks all test suite improvements

## Solution Required
All references in Examples/Package.swift need to be updated from:
```swift
.product(name: "NDKSwift", package: "NDKSwift")
```

To:
```swift
.product(name: "NDKSwift", package: "NDKSwift-z94ws0")
```

This affects approximately 10 target definitions in the file.

## Root Cause
The package appears to have been renamed or moved, but the Examples package wasn't updated to reflect the new package name.