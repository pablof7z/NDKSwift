//
//  APITypes.swift
//  CashuSwift
//
//  Created by Assistant on 2025-01-11.
//

import Foundation

// Swap API Types
public struct CashuSwiftSwapRequest: Codable {
    public let inputs: [CashuSwift.Proof]
    public let outputs: [CashuSwift.Output]
    
    public init(inputs: [CashuSwift.Proof], outputs: [CashuSwift.Output]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct CashuSwiftSwapResponse: Codable {
    public let signatures: [CashuSwift.Promise]
    
    public init(signatures: [CashuSwift.Promise]) {
        self.signatures = signatures
    }
}

// Restore API Types
public struct CashuSwiftRestoreRequest: Codable {
    public let outputs: [CashuSwift.Output]
    
    public init(outputs: [CashuSwift.Output]) {
        self.outputs = outputs
    }
}

public struct CashuSwiftRestoreResponse: Codable {
    public let outputs: [CashuSwift.Output]
    public let signatures: [CashuSwift.Promise]
    
    public init(outputs: [CashuSwift.Output], signatures: [CashuSwift.Promise]) {
        self.outputs = outputs
        self.signatures = signatures
    }
}

public struct CashuSwiftKeysetRestoreResult: Sendable {
    public let keysetID: String
    public let derivationCounter: Int
    public let unitString: String
    public let proofs: [CashuSwift.Proof]
    public let inputFeePPK: Int
    
    public init(keysetID: String, derivationCounter: Int, unitString: String, proofs: [CashuSwift.Proof], inputFeePPK: Int) {
        self.keysetID = keysetID
        self.derivationCounter = derivationCounter
        self.unitString = unitString
        self.proofs = proofs
        self.inputFeePPK = inputFeePPK
    }
}

// Type aliases for backward compatibility
extension CashuSwift {
    public typealias SwapRequest = CashuSwiftSwapRequest
    public typealias SwapResponse = CashuSwiftSwapResponse
    public typealias RestoreRequest = CashuSwiftRestoreRequest
    public typealias RestoreResponse = CashuSwiftRestoreResponse
    public typealias KeysetRestoreResult = CashuSwiftKeysetRestoreResult
}