# Low-Risk Improvements for NDKSwift

After exploring the codebase, I've identified several low-risk, high-value improvements that follow DRY/YAGNI/SRP/KISS principles:

## 1. HTTP Constants Usage
**Issue**: The "User-Agent" header is hardcoded in `NIP05Manager.swift` (line 316)
```swift
request.setValue("NDKSwift", forHTTPHeaderField: "User-Agent")
```
**Fix**: Add `headerUserAgent` to `HTTPConstants.swift` and use it consistently.

## 2. Example URLs in Documentation
**Issue**: Example relay URLs are hardcoded in documentation/comments instead of using `RelayConstants`
- `NDKRelay.swift:313`: Uses `"wss://relay.example.com"` 
- `NDKEventTracker.swift:15,18`: Uses `"wss://relay.damus.io"`
- `NDKEventBuilder.swift:332`: Uses `"wss://relay.example.com"`

**Fix**: Use `RelayConstants.damus` or create a `RelayConstants.example` for documentation.

## 3. Duplicate Hex Validation
**Issue**: `NDKEvent.swift` has its own `isHexDigit` extension (line 389) when `HexValidator` utility already exists
```swift
private extension Character {
    var isHexDigit: Bool {
        return ("0" ... "9").contains(self) || ("a" ... "f").contains(self) || ("A" ... "F").contains(self)
    }
}
```
**Fix**: Remove the private extension and use `HexValidator` instead.

## 4. File Organization - Constants Directory
**Issue**: `RelayConstants.swift` is in `/Constants` directory while other constants (`HTTPConstants`, `NetworkConstants`, `NostrConstants`, `StringConstants`) are in `/Utils`
**Fix**: Move `RelayConstants.swift` to `/Utils` for consistency.

## 5. Deprecated Code Cleanup
**Issue**: Several files contain deprecated NIP-04 code that's maintained for backward compatibility
- Multiple files reference NIP-04 as deprecated
- Could be moved to a legacy module for cleaner separation

**Fix**: Consider creating a `Legacy` subdirectory for deprecated protocols (optional, discuss with team first).

## 6. Magic Numbers in Constants
**Issue**: Some timeout values and limits could be better documented
**Fix**: Add inline comments explaining the rationale for specific values in `NetworkConstants.swift`

## 7. Import Optimization
**Issue**: Some files import both `Foundation` and specific frameworks when Foundation might be sufficient
**Fix**: Review imports and remove redundant ones (requires testing to ensure nothing breaks).

## Implementation Priority

1. **High Priority (Quick wins)**:
   - Add missing HTTP constants
   - Fix hardcoded example URLs
   - Remove duplicate hex validation

2. **Medium Priority**:
   - Move RelayConstants to Utils directory
   - Document magic numbers in constants

3. **Low Priority (Discuss first)**:
   - Organize deprecated code
   - Optimize imports

All these improvements are low-risk because they:
- Don't change any public APIs
- Don't affect functionality
- Improve code consistency and maintainability
- Follow existing patterns in the codebase
- Can be implemented incrementally