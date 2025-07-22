# JSONCoding Usage Audit

## Summary
Found 6 files in the Examples directory that use `JSONEncoder()` or `JSONDecoder()` directly instead of using the centralized `JSONCoding` utility from NDKSwift.

## Files Using Direct JSON Encoding/Decoding

### 1. **DebugKind0Fetcher/main.swift**
- **Line 67**: `try? JSONDecoder().decode(NDKUserProfile.self, from: data)`
- **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: data)`

### 2. **Apps/NutsackiOS/Sources/NutsackiOS/DataSources/NostrDataSources.swift**
- **Line 57**: Uses `JSONSerialization.jsonObject(with: data)` - This is correct as it needs raw dictionary
- **Line 112**: `try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data())`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data())`
- **Line 160**: `try? JSONDecoder().decode(NDKUserProfile.self, from: latestEvent.content.data(using: .utf8) ?? Data())`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: latestEvent.content.data(using: .utf8) ?? Data())`

### 3. **Apps/NutsackiOS/Sources/NutsackiOS/Views/Wallet/RecentTransactionsView.swift**
- **Line 204**: `try? JSONDecoder().decode(NDKUserProfile.self, from: profileData)`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: profileData)`

### 4. **GettingStarted/Example08_PublishWithNIP46.swift**
- **Line 101**: `try? JSONDecoder().decode(NDKUserProfile.self, from: profileData)`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: profileData)`

### 5. **Apps/NutsackiOS/Sources/NutsackiOS/Views/Wallet/NutzapView.swift**
- **Line 345**: `try? JSONDecoder().decode(NDKUserProfile.self, from: profileData)`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: profileData)`
- **Line 513**: `try? JSONDecoder().decode(NDKUserProfile.self, from: profileData)`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: profileData)`

### 6. **Apps/NutsackiOS/Sources/NutsackiOS/Views/Auth/ImportAccountView.swift**
- **Line 110**: `try? JSONDecoder().decode(NDKUserProfile.self, from: profileData)`
  - **Should use**: `JSONCoding.safeDecode(NDKUserProfile.self, from: profileData)`

## Benefits of Using JSONCoding

1. **Consistency**: All JSON operations use the same configuration (sorted keys, no escaping slashes)
2. **Error Handling**: Better error messages with NDKError types
3. **Performance**: Reuses encoder/decoder instances instead of creating new ones
4. **Maintainability**: Central place to update JSON handling behavior
5. **Type Safety**: Specialized methods for different use cases (Nostr messages, snake_case, etc.)

## Recommendations

All instances of direct `JSONDecoder()` usage should be replaced with the appropriate `JSONCoding` methods:
- Use `JSONCoding.safeDecode()` for optional decoding (replacing `try?`)
- Use `JSONCoding.decode()` for required decoding (replacing `try`)
- Use `JSONCoding.encode()` or `JSONCoding.encodeToString()` for encoding