import NDKSwiftCore
// MARK: - Common Wallet Imports

/// This file provides common imports for wallet-related functionality.
/// Import this file to automatically get access to all commonly used wallet dependencies.
///
/// Usage:
/// ```swift
/// import WalletImports
/// ```

@_exported import Foundation
import CashuSwift

// MARK: - Type Aliases

/// Common type aliases for wallet functionality
public typealias CashuToken = CashuSwift.Token
public typealias CashuProof = CashuSwift.Proof
public typealias CashuKeyset = CashuSwift.Keyset
public typealias CashuMint = CashuSwift.Mint
// CashuError type alias removed - not available in CashuSwift

// MARK: - Constants

/// Common constants used across wallet implementations
public enum WalletConstants {
    /// Default unit for ecash transactions
    public static let defaultUnit = "sat"
    
    /// Maximum retry attempts for mint operations
    public static let maxMintRetries = 3
    
    /// Default timeout for mint operations
    public static let mintTimeout: TimeInterval = 30
    
    /// Maximum proofs per transaction (for batching)
    public static let maxProofsPerTransaction = 100
    
    /// Cache duration for mint info
    public static let mintInfoCacheDuration: TimeInterval = 3600 // 1 hour
}

// MARK: - Common Extensions

// Data.hexString extension removed - already exists in DataHexExtensions.swift
// String.hexData extension removed - use String.hexDecoded() from DataHexExtensions.swift instead