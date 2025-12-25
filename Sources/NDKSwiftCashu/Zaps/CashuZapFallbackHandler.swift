import CashuSwift
import Foundation
import NDKSwiftCore

/// Fallback handler for funding Nutzaps via Lightning when no direct Cashu provider is available
public class CashuZapFallbackHandler: ZapFallbackHandler {

    public init() {}

    public func tryFallback(
        manager: NDKZapManager,
        protocol zapProtocol: NDKZapProtocol,
        prepared: PreparedZap,
        preferredProvider: String?
    ) async throws -> ZapResult? {
        // Only handle Nutzap protocol
        guard zapProtocol.type == .nutzap,
              let nutzapProtocol = zapProtocol as? NDKNutzapProtocol,
              let nutzapRequest = prepared.paymentRequest as? NutzapPaymentRequest else {
            return nil
        }

        NDKLogger.log(.debug, category: .wallet, "Attempting Lightning-to-Nutzap fallback")

        // Try Lightning-based funding
        return try await fundNutzapViaLightning(
            manager: manager,
            nutzapProtocol: nutzapProtocol,
            prepared: prepared,
            nutzapRequest: nutzapRequest,
            preferredProvider: preferredProvider
        )
    }

    /// Fund a Nutzap using Lightning payment to mint
    private func fundNutzapViaLightning(
        manager: NDKZapManager,
        nutzapProtocol: NDKNutzapProtocol,
        prepared: PreparedZap,
        nutzapRequest: NutzapPaymentRequest,
        preferredProvider: String?
    ) async throws -> ZapResult {
        // Try each accepted mint
        var mintAttempts = 0
        var lastError: Error?

        for mintURL in nutzapRequest.acceptedMints {
            mintAttempts += 1
            let mintHost = mintURL.host ?? mintURL.absoluteString

            do {
                // Create mint quote
                let quote: MintQuote
                do {
                    quote = try await nutzapProtocol.createMintQuote(
                        invoice: "",
                        mint: mintURL,
                        amount: nutzapRequest.amountSats
                    )
                } catch {
                    lastError = ZapError.mintQuoteFailed(mint: mintHost, reason: error.localizedDescription)
                    continue
                }

                // Create Lightning request for the mint's invoice
                let lightningRequest = LightningInvoiceRequest(
                    invoice: quote.invoice,
                    amountSats: quote.amount,
                    recipient: "Mint: \(mintHost)"
                )

                // Find a Lightning provider
                let lightningProvider: (any NDKPaymentProvider)?
                do {
                    lightningProvider = try await manager.selectPaymentProvider(
                        for: lightningRequest,
                        preferredId: preferredProvider
                    )
                } catch {
                    NDKLogger.log(.warning, category: .wallet, "Failed to select Lightning provider for mint quote: \(error.localizedDescription)")
                    lastError = ZapError.noWalletConfigured
                    continue
                }

                guard let lightningProvider = lightningProvider else {
                    lastError = ZapError.noWalletConfigured
                    continue
                }

                // Pay the Lightning invoice
                do {
                    _ = try await lightningProvider.fulfill(lightningRequest)
                } catch {
                    lastError = ZapError.paymentFailed(error.localizedDescription)
                    continue
                }

                // Mint tokens using the paid invoice
                let proofs: [CashuSwift.Proof]
                do {
                    proofs = try await mintTokensWithQuote(
                        quote: quote,
                        recipientP2PK: nutzapRequest.recipientP2PK
                    )
                } catch {
                    lastError = ZapError.mintTokenCreationFailed(mint: mintHost, reason: error.localizedDescription)
                    continue
                }

                // Create Cashu confirmation
                let cashuConfirmation = CashuPaymentConfirmation(
                    proofs: proofs,
                    change: nil,
                    mintURL: mintURL
                )

                // Complete the zap
                return try await nutzapProtocol.completeZap(
                    prepared: prepared,
                    confirmation: cashuConfirmation
                )

            } catch {
                lastError = error
                continue
            }
        }

        // All mints failed
        if mintAttempts > 0 {
            throw ZapError.allMintsFailed(attempts: mintAttempts)
        } else {
            throw lastError ?? ZapError.paymentFailed("No mints available")
        }
    }

    /// Mint tokens using a paid quote
    private func mintTokensWithQuote(
        quote: MintQuote,
        recipientP2PK: String
    ) async throws -> [CashuSwift.Proof] {
        // Connect to the mint and load keysets
        let cashuMint = try await CashuSwift.loadMint(url: quote.mint)

        do {
            // First, check if the quote has been paid
            let quoteState = try await CashuSwift.mintQuoteState(
                for: quote.id,
                mint: cashuMint
            )

            guard quoteState.state == .paid else {
                throw ZapError.paymentFailed("Lightning invoice not yet paid")
            }

            // Generate a seed for deterministic output generation
            let seed = Crypto.randomBytes(count: Crypto.Constants.privateKeySize).hexString

            // Create a properly typed mint quote from our stored data
            let mintQuoteData: [String: Any] = [
                "quote": quote.id,
                "amount": Int(quote.amount),
                "request": quote.invoice,
                "state": "PAID",
                "expiry": Int(Timestamp.from(quote.expiry))
            ]

            let mintQuote = try JSONCoding.decodeFromDictionary(CashuSwift.Bolt11.MintQuote.self, from: mintQuoteData)

            // Issue tokens for the paid quote
            let issueResult = try await CashuSwift.issue(
                for: mintQuote,
                mint: cashuMint,
                seed: seed
            )

            if case .fail = issueResult.dleqResult {
                NDKLogger.log(.warning, category: .general, "⚠️ Warning: DLEQ verification failed for minted proofs")
            }

            // Now we need to swap these proofs to P2PK-locked ones
            let sendResult = try await CashuSwift.send(
                inputs: issueResult.proofs,
                mint: cashuMint,
                amount: Int(quote.amount),
                seed: seed,
                lockToPublicKey: recipientP2PK
            )

            // Extract the locked proofs from the token
            guard let mintProofs = sendResult.token.proofsByMint[quote.mint.absoluteString] else {
                throw ZapError.mintTokenCreationFailed(
                    mint: quote.mint.host ?? quote.mint.absoluteString,
                    reason: "No proofs returned from mint"
                )
            }

            return mintProofs

        } catch {
            throw ZapError.mintTokenCreationFailed(
                mint: quote.mint.host ?? quote.mint.absoluteString,
                reason: error.localizedDescription
            )
        }
    }
}
