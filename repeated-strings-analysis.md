# Repeated String Literals Analysis for NDKSwift

## Overview
This analysis identifies repeated string literals in the NDKSwift codebase that could be consolidated into constants to improve maintainability and reduce the risk of typos.

## Findings

### 1. Error Messages (High Priority)

#### Crypto Operations (8+ occurrences)
- `"Encryption"` - Used in crypto operation errors across multiple files
- `"Decryption"` - Used in crypto operation errors across multiple files  
- `"Signing"` - Used in crypto operation errors across multiple files
- `"Verification"` - Used in crypto operation errors
- `"Key derivation"` - Used 2+ times in NDKPrivateKeySigner

#### Configuration Errors (21+ occurrences)
- `"No signer configured"` - Appears 3+ times in NDK+Interactions.swift
- `"NDK instance not set"` - Appears 5 times in NDKUser.swift
- `"NDK not available"` - Appears 2+ times in NDKZapManager.swift
- `"NDK reference lost"` - Appears 4 times in NDKEventManager.swift

#### Validation Errors (31+ occurrences)
- `"64 character hex"` - Used for hex validation in multiple files
- `"32 bytes"` - Used for key validation
- `"Invalid URL"` - Used for URL validation
- `"Invalid event"` - Used for event validation  
- `"Missing required"` - Used for missing field validation

#### Operation Failures (Multiple occurrences)
- `"Failed to"` - Common prefix for operation failures
- `"Failed to encrypt"` - NDKBunkerSigner
- `"Failed to decrypt"` - NDKBunkerSigner
- `"Failed to get public key"` - NDKBunkerSigner
- `"Failed to parse"` - Multiple locations
- `"Failed to connect"` - Network operations

### 2. Log Messages (49+ occurrences in BunkerSigner alone)

#### BunkerSigner Log Prefix
- `"[BunkerSigner]"` - Appears 49+ times in NDKBunkerSigner.swift alone
- This prefix is repeated in every log message in the file

#### Common Log Patterns
- `"Successfully connected to relay:"` 
- `"Failed to connect to relay"`
- `"Connecting to relay:"`
- `"Added relay:"`
- `"Starting connection process..."`
- `"Using relays:"`

### 3. JSON Keys (Multiple occurrences)

#### Signer Serialization Keys
- `"privateKey"` - Used in signer serialization/deserialization
- `"publicKey"` - Used in multiple contexts
- `"bunkerPubkey"` - BunkerSigner serialization
- `"userPubkey"` - BunkerSigner serialization
- `"relayUrls"` - Used in multiple contexts
- `"secret"` - Authentication contexts
- `"connectionType"` - BunkerSigner serialization
- `"localSignerData"` - BunkerSigner serialization

#### RPC Method Names
- `"connect"` - Bunker RPC method (3+ occurrences)
- `"sign_event"` - Bunker RPC method
- `"get_public_key"` - Bunker RPC method
- `"nip04_encrypt"` - Bunker RPC method
- `"nip44_encrypt"` - Bunker RPC method
- `"nip04_decrypt"` - Bunker RPC method
- `"nip44_decrypt"` - Bunker RPC method

#### URL Parameters
- `"pubkey"` - Query parameter name
- `"relay"` - Query parameter name  
- `"secret"` - Query parameter name
- `"name"` - Query parameter name
- `"url"` - Query parameter name
- `"image"` - Query parameter name
- `"perms"` - Query parameter name

### 4. String Identifiers

#### Type Identifiers
- `"bunker"` - Connection type identifier
- `"nostrConnect"` - Connection type identifier
- `"nip05"` - Connection type identifier
- `"privatekey"` - Signer type identifier

#### URL Schemes
- `"bunker://"` - URL scheme
- `"nostrconnect://"` - URL scheme

### 5. Format Strings

#### Data Format Descriptions
- `"private key"` - Used in error messages
- `"public key"` - Used in error messages
- `"relay URL"` - Used in error messages
- `"client secret"` - Used in error messages
- `"wallet public key"` - Used in error messages

## Recommendations

### 1. Create Error Message Constants
```swift
enum ErrorMessages {
    static let noSignerConfigured = "No signer configured"
    static let ndkInstanceNotSet = "NDK instance not set"
    static let ndkNotAvailable = "NDK not available"
    static let ndkReferenceLost = "NDK reference lost"
    // ... etc
}
```

### 2. Create Crypto Operation Constants
```swift
enum CryptoOperations {
    static let encryption = "Encryption"
    static let decryption = "Decryption"
    static let signing = "Signing"
    static let verification = "Verification"
    static let keyDerivation = "Key derivation"
}
```

### 3. Create JSON Key Constants
```swift
enum JSONKeys {
    enum Signer {
        static let privateKey = "privateKey"
        static let publicKey = "publicKey"
        static let bunkerPubkey = "bunkerPubkey"
        static let userPubkey = "userPubkey"
        static let relayUrls = "relayUrls"
        static let secret = "secret"
        static let connectionType = "connectionType"
        static let localSignerData = "localSignerData"
    }
    
    enum RPC {
        static let connect = "connect"
        static let signEvent = "sign_event"
        static let getPublicKey = "get_public_key"
        static let nip04Encrypt = "nip04_encrypt"
        static let nip44Encrypt = "nip44_encrypt"
        static let nip04Decrypt = "nip04_decrypt"
        static let nip44Decrypt = "nip44_decrypt"
    }
}
```

### 4. Create Log Message Constants
```swift
enum LogPrefixes {
    static let bunkerSigner = "[BunkerSigner]"
}
```

### 5. Create Validation Constants
```swift
enum ValidationRequirements {
    static let hexLength64 = "64 character hex"
    static let keySize32Bytes = "32 bytes"
}
```

## Impact

By consolidating these repeated strings into constants:
1. **Reduced typo risk** - Single source of truth for each string
2. **Better maintainability** - Changes only need to be made in one place
3. **Improved searchability** - Find all usages through constant references
4. **Type safety** - Compiler can catch typos in constant names
5. **Documentation** - Constants can have doc comments explaining their usage

## Priority Order

1. **High Priority**: Error messages and JSON keys (used in critical paths)
2. **Medium Priority**: Log messages (especially the repeated BunkerSigner prefix)
3. **Low Priority**: Format strings and descriptions (less critical but still beneficial)