# Dead Code Analysis for NDKSwift

## Summary
This analysis identifies potentially dead code and unused utilities in the NDKSwift codebase, focusing on the Utils and Core/Utilities directories.

## Unused or Rarely Used Code

### 1. Thread-Safe Collections (`Utils/ThreadSafeCollections.swift`)
- **EventCollection** - Not used anywhere in the codebase
- **CallbackCollection** - Not used anywhere in the codebase  
- **StateManager** - Not used anywhere in the codebase
- **Status**: These appear to be example implementations that were never adopted

### 2. Optimistic Event Source (`Core/Utilities/OptimisticEventSource.swift`)
- **OptimisticEventSource** class - Only referenced in its own file
- **Status**: Appears to be dead code, possibly from a removed or unimplemented feature

### 3. Array Extensions (`Utils/ArrayExtensions.swift`)
- **`asyncFilter`** - Only used in one place (NDKPool.swift)
- **`.set` property** - Used in a few places
- **`[safe]` subscript** - Used in 5 files
- **Status**: Partially used, but `asyncFilter` has minimal usage

### 4. Content Tagging (`Utils/ContentTagger.swift`)
- **TagBuilder** struct - Not used anywhere in the codebase
- **Status**: The main ContentTagger functions are used, but TagBuilder appears to be dead code

### 5. ID Generator (`Utils/IDGenerator.swift`)
- **sharedIDGenerator** - Only used in NDKFetchingStrategy.swift
- **randomId** static method - Not used anywhere
- **Status**: Minimal usage, could potentially be inlined

### 6. Constants with No Usage
Several constants in various files have no references:
- **HTTPConstants**: All constants are used
- **StringConstants**: All constants are used
- **NetworkConstants**: All constants are used
- **NostrConstants**: All constants are used
- **EventKind**: Some rarely used kinds like:
  - `recommendRelay` (kind 2) - Only used in NDKEvent+Interactions
  - `badgeAward` (kind 8) - Not used
  - `genericRepost` (kind 16) - Not used
  - `categorizedPeople` (kind 30000) - Not used
  - `categorizedBookmarks` (kind 30001) - Not used
  - `profileBadges` (kind 30008) - Not used
  - `badgeDefinition` (kind 30009) - Not used

### 6. Type Aliases
- **RequirementID** in `DataSource/NDKDataRequirementManager.swift` - Used only within that file

## Recommendations

### High Priority (Definitely Remove)
1. **ThreadSafeCollections.swift** - Entire file is unused
2. **OptimisticEventSource.swift** - Entire file is unused
3. **TagBuilder** struct in ContentTagger.swift

### Medium Priority (Consider Removing)
1. **IDGenerator.randomId()** method - Not used
2. **ArrayExtensions.asyncFilter** - Only one usage, could be inlined
3. Unused EventKind constants for badge and categorized events

### Low Priority (Keep for Now)
1. **ArrayExtensions.[safe]** - Used in 5 files, provides safety
2. **IDGenerator** class - Minimal usage but provides consistent ID generation
3. **Bech32** utilities - Well used throughout
4. **HexValidator** - Well used throughout
5. **RetryPolicy** - Used for relay connections

## Files That Are Well-Used
- Crypto.swift
- DataExtensions.swift
- FileManagerExtensions.swift
- URLNormalizer.swift
- URLUtils.swift
- JSONCoding.swift
- ImetaUtils.swift
- NostrIdentifier.swift
- ContentParser.swift
- NDKLogger.swift
- NDKParsedContent.swift

## Next Steps
1. Remove the high priority dead code files
2. Review medium priority items with the team
3. Consider consolidating some utility functions
4. Add documentation for why certain unused constants are kept (if they're part of the protocol spec)