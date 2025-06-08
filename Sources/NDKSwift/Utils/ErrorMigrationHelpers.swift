import Foundation

/// Helper utilities for migrating to the unified error system
public enum ErrorMigration {
    
    /// Convert any error to NDKUnifiedError
    public static func unify(_ error: Error) -> NDKUnifiedError {
        switch error {
        case let unified as NDKUnifiedError:
            return unified
            
        case let ndkError as NDKError:
            return ndkError.unified
            
        case let bech32Error as Bech32.Bech32Error:
            return unifyBech32Error(bech32Error)
            
        case let blossomError as BlossomError:
            return unifyBlossomError(blossomError)
            
        case let cryptoError as Crypto.CryptoError:
            return unifyCryptoError(cryptoError)
            
        case let urlError as URLNormalizationError:
            return unifyURLError(urlError)
            
        case let fetchError as FetchError:
            return unifyFetchError(fetchError)
            
        case is CancellationError:
            return .runtime(.cancelled)
            
        case let nsError as NSError where nsError.domain == NSURLErrorDomain:
            return unifyNSURLError(nsError)
            
        default:
            return .runtime(.unknown, underlying: error)
        }
    }
    
    // MARK: - Specific Error Conversions
    
    private static func unifyBech32Error(_ error: Bech32.Bech32Error) -> NDKUnifiedError {
        switch error {
        case let .invalidCharacter(char):
            return .validation(.invalidInput, context: ["character": String(char), "encoding": "bech32"])
        case .invalidChecksum:
            return .validation(.invalidInput, context: ["reason": "invalid_checksum", "encoding": "bech32"])
        case .invalidLength:
            return .validation(.invalidInput, context: ["reason": "invalid_length", "encoding": "bech32"])
        case .invalidHRP:
            return .validation(.invalidInput, context: ["reason": "invalid_hrp", "encoding": "bech32"])
        case .invalidData:
            return .validation(.invalidInput, context: ["reason": "invalid_data", "encoding": "bech32"])
        case .invalidPadding:
            return .validation(.invalidInput, context: ["reason": "invalid_padding", "encoding": "bech32"])
        }
    }
    
    private static func unifyBlossomError(_ error: BlossomError) -> NDKUnifiedError {
        switch error {
        case .invalidURL:
            return .validation(.invalidInput, context: ["type": "url", "protocol": "blossom"])
        case .invalidResponse:
            return .network(.invalidMessage, context: ["protocol": "blossom"])
        case .unauthorized:
            return .network(.unauthorized, context: ["protocol": "blossom"])
        case let .serverError(code, message):
            return .network(.serverError, context: ["code": code, "message": message ?? "", "protocol": "blossom"])
        case .fileTooLarge:
            return .validation(.invalidInput, context: ["reason": "file_too_large", "protocol": "blossom"])
        case .unsupportedMimeType:
            return .validation(.invalidInput, context: ["reason": "unsupported_mime_type", "protocol": "blossom"])
        case .blobNotFound:
            return .storage(.fileNotFound, context: ["type": "blob", "protocol": "blossom"])
        case let .uploadFailed(message):
            return .network(.connectionFailed, context: ["operation": "upload", "message": message, "protocol": "blossom"])
        case let .networkError(underlying):
            return .network(.connectionFailed, context: ["protocol": "blossom"], underlying: underlying)
        case .invalidSHA256:
            return .validation(.invalidInput, context: ["type": "sha256", "protocol": "blossom"])
        }
    }
    
    private static func unifyCryptoError(_ error: Crypto.CryptoError) -> NDKUnifiedError {
        switch error {
        case .invalidKeyLength:
            return .crypto(.keyDerivationFailed, context: ["reason": "invalid_key_length"])
        case .invalidSignatureLength:
            return .crypto(.verificationFailed, context: ["reason": "invalid_signature_length"])
        case .signingFailed:
            return .crypto(.signingFailed)
        case .verificationFailed:
            return .crypto(.verificationFailed)
        case .invalidPoint:
            return .crypto(.keyDerivationFailed, context: ["reason": "invalid_elliptic_curve_point"])
        case .invalidScalar:
            return .crypto(.keyDerivationFailed, context: ["reason": "invalid_scalar_value"])
        }
    }
    
    private static func unifyURLError(_ error: URLNormalizationError) -> NDKUnifiedError {
        switch error {
        case .invalidURL:
            return .validation(.invalidInput, context: ["type": "url"])
        }
    }
    
    private static func unifyFetchError(_ error: FetchError) -> NDKUnifiedError {
        switch error {
        case let .relayError(url, message):
            return .network(.serverError, context: ["relay": url, "message": message])
        case let .insufficientRelays(required, successful):
            return .network(.connectionFailed, context: ["reason": "insufficient_relays", "required": required, "successful": successful])
        case .timeout:
            return .network(.timeout)
        case .cancelled:
            return .runtime(.cancelled)
        }
    }
    
    private static func unifyNSURLError(_ error: NSError) -> NDKUnifiedError {
        switch error.code {
        case NSURLErrorTimedOut:
            return .network(.timeout, underlying: error)
        case NSURLErrorCancelled:
            return .runtime(.cancelled, underlying: error)
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return .network(.connectionFailed, underlying: error)
        case NSURLErrorNotConnectedToInternet:
            return .network(.connectionFailed, context: ["reason": "no_internet"], underlying: error)
        default:
            return .network(.connectionFailed, underlying: error)
        }
    }
}

/// Extension to throw unified errors from legacy code
extension NDKUnifiedError {
    /// Throw a unified error, converting from legacy if needed
    public static func throwUnified<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let unified as NDKUnifiedError {
            throw unified
        } catch {
            throw ErrorMigration.unify(error)
        }
    }
    
    /// Execute async code and convert errors to unified
    public static func throwUnifiedAsync<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let unified as NDKUnifiedError {
            throw unified
        } catch {
            throw ErrorMigration.unify(error)
        }
    }
}

/// Protocol for types that can provide error context
public protocol ErrorContextProvider {
    var errorContext: [String: Any] { get }
}

/// Extension to add context to errors
extension NDKUnifiedError {
    public func withContext(from provider: ErrorContextProvider) -> NDKUnifiedError {
        var mergedContext = context
        for (key, value) in provider.errorContext {
            mergedContext[key] = value
        }
        
        return NDKUnifiedError(
            category: category,
            specific: specific,
            context: mergedContext,
            underlying: underlying
        )
    }
    
    public func withContext(_ key: String, _ value: Any) -> NDKUnifiedError {
        var mergedContext = context
        mergedContext[key] = value
        
        return NDKUnifiedError(
            category: category,
            specific: specific,
            context: mergedContext,
            underlying: underlying
        )
    }
}