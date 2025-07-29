// MARK: - Common Wallet Imports

/// This file provides common imports for wallet-related functionality.
/// Import this file to automatically get access to all commonly used wallet dependencies.
///
/// Usage:
/// ```swift
/// import WalletImports
/// ```

@_exported import Foundation
@_exported import CashuSwift

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

public extension String {
    /// Convert hex string to data for wallet operations
    var hexData: Data? {
        var data = Data()
        var hex = self
        
        // Remove "0x" prefix if present
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        guard hex.count % 2 == 0 else { return nil }
        
        while !hex.isEmpty {
            let byte = String(hex.prefix(2))
            hex = String(hex.dropFirst(2))
            if let num = UInt8(byte, radix: 16) {
                data.append(num)
            } else {
                return nil
            }
        }
        
        return data
    }
}