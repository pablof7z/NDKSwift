import Foundation
import CashuSwift

/// Functions for handling nutzap operations (P2PK-locked tokens via Nostr events)
public enum Nutzap {

    // MARK: - Sending Nutzaps

    /// Send a nutzap to a recipient
    /// - Parameters:
    ///   - wallet: The NIP60 wallet to send from
    ///   - amount: Amount to send in satoshis
    ///   - recipient: Recipient's Nostr public key
    ///   - recipientP2PKKey: Recipient's P2PK key (from their kind:10019 event or payment request)
    ///   - comment: Optional comment for the nutzap
    ///   - eventId: Optional event ID if nutzapping an event
    ///   - mints: Available mints
    ///   - proofStateManager: Proof state manager
    ///   - eventManager: Event manager for history
    ///   - ndk: NDK instance
    ///   - signer: Signer for the nutzap event
    public static func send(
        wallet: NIP60Wallet,
        amount: Int64,
        to recipient: PublicKey,
        recipientP2PKKey: String,
        comment: String? = nil,
        eventId: String? = nil,
        mints: [String: CashuSwift.Mint],
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        ndk: NDK,
        signer: NDKSigner
    ) async throws -> NDKEvent {
        // Get mints with sufficient balance, ordered by balance (highest first)
        // Add a buffer for fees (typically 1-2 sats for small amounts)
        let amountWithFeeBuffer = amount + 2
        let viableMintURLs = await proofStateManager.getMintsWithSufficientBalance(amount: amountWithFeeBuffer)

        guard !viableMintURLs.isEmpty else {
            throw NDKError.insufficientBalance(amount: amount)
        }

        // Use the provided P2PK key (should come from payment request)
        let recipientP2PK = recipientP2PKKey

        // Try each viable mint until one succeeds
        var lastError: Error?
        for mintURL in viableMintURLs {
            // Load mint dynamically
            guard let mintUrl = URL(string: mintURL) else {
                NDKLogger.log(.error, category: .general, "\(ErrorMessageConstants.invalid("mint URL")): \(mintURL)")
                continue
            }

            let mint: CashuSwift.Mint
            do {
                mint = try await wallet.mints.loadMint(url: mintUrl)
            } catch {
                NDKLogger.log(.error, category: .general, "\(ErrorMessageConstants.failedTo("load mint \(mintURL)")): \(error)")
                lastError = error
                continue
            }
            // Get available proofs and use CashuSwift's pick function to handle fee calculation
            let availableProofs = await proofStateManager.getAvailableProofs(mint: mintURL)
            guard let pickResult = CashuSwift.pick(availableProofs, amount: Int(amount), mint: mint) else {
                lastError = NDKError.insufficientBalance(amount: amount)
                continue
            }

            // Convert ProofRepresenting to concrete Proof types
            let selectedProofs = pickResult.selected.compactMap { $0 as? CashuSwift.Proof }
            guard selectedProofs.count == pickResult.selected.count else {
                lastError = NDKError.invalidProof(ErrorMessageConstants.failedTo("convert selected proofs"))
                continue
            }

            let calculatedFee = pickResult.fee

            NDKLogger.log(.debug, category: .wallet, "Selected \(selectedProofs.count) proofs for nutzap. Amount: \(amount), Fee: \(calculatedFee)")

            // Reserve proofs
            do {
                try await proofStateManager.reserveProofs(selectedProofs)
            } catch {
                lastError = error
                continue
            }

            do {
                // Create P2PK-locked proofs
                let (lockedProofs, change) = try await lockProofsForRecipient(
                    proofs: selectedProofs,
                    amount: amount,
                    recipientPubkey: recipientP2PK,
                    mint: mint,
                    mintURL: mintURL
                )

                // Create nutzap event using proper framework
                let token = CashuSwift.Token(
                    proofs: [mintURL: lockedProofs],
                    unit: "sat"
                )

                let nutzapWrapper = try await NDKNutzapEvent.createAndPublish(
                    ndk: ndk,
                    token: token,
                    mintURL: mintURL,
                    recipient: recipient,
                    comment: comment,
                    eventId: eventId,
                    signer: signer
                )

                let nutzapEvent = nutzapWrapper.event

                // Update wallet state
                await proofStateManager.markProofsAsDeleted(selectedProofs)
                if let changeProofs = change {
                    for proof in changeProofs {
                        await proofStateManager.addProof(proof, mint: mintURL)
                    }
                }

                // Update token events
                let stateChange = WalletStateChange(
                    store: change ?? [],
                    destroy: selectedProofs,
                    mint: mintURL,
                    memo: "Send nutzap"
                )
                _ = try await wallet.update(stateChange: stateChange)

                // Create spending history
                try await eventManager.createSpendingHistoryEvent(
                    direction: .out,
                    amount: amount,
                    memo: comment ?? "Nutzap sent",
                    destroyedEventIds: nil,
                    createdEventIds: nil,
                    redeemedEventId: nil,
                    signer: signer
                )

                // Add to transaction history
                let nutzapData = NutzapData(
                    recipientPubkey: recipient,
                    nutzapEventId: nutzapEvent.id,
                    comment: comment,
                    eventBeingZapped: eventId
                )

                let transaction = WalletTransaction(
                    type: .nutzapSent,
                    amount: amount,
                    direction: .outgoing,
                    status: .completed,
                    memo: comment ?? "Nutzap sent",
                    mint: mintURL,
                    timestamp: Date(),
                    events: TransactionEvents(nutzapEventId: nutzapEvent.id),
                    lookupKeys: TransactionLookupKeys(nutzapEventId: nutzapEvent.id, recipientPubkey: recipient),
                    nutzapData: nutzapData
                )

                await wallet.transactionHistory.addManualTransaction(transaction)

                return nutzapEvent

            } catch {
                // Release proofs on failure and try next mint
                await proofStateManager.releaseProofs(selectedProofs)
                lastError = error
                NDKLogger.log(.warning, category: .general, "Nutzap failed with mint \(mintURL): \(error). Trying next mint...")
                continue
            }
        }

        // If we reach here, all mints failed
        throw lastError ?? NDKError.insufficientBalance(amount: amount)
    }

    // MARK: - Receiving Nutzaps

    /// Process an incoming nutzap event
    public static func processIncoming(
        wallet: NIP60Wallet,
        event: NDKEvent,
        mints: [String: CashuSwift.Mint],
        keysets: [String: CashuSwift.Keyset],
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        p2pkManager: P2PKManager,
        ndk: NDK,
        signer: NDKSigner
    ) async throws -> NutzapRedemptionResult {
        // Check if this nutzap is for us
        let privateKey = try await p2pkManager.getOrCreatePrivateKey()
        let ourPubkeyHex = try await p2pkManager.getCashuPublicKey()

        NDKLogger.log(.debug, category: .wallet, "Processing nutzap with our P2PK pubkey: \(ourPubkeyHex)")

        // Verify p tag points to our Nostr pubkey
        let pTags = event.tags.pubkeyTags
        guard let recipientTag = pTags.first,
              recipientTag.count > 1 else {
            NDKLogger.log(.debug, category: .wallet, "No recipient tag in nutzap - ignoring")
            throw NutzapRedemptionError.invalidProofs(reason: "No recipient tag in nutzap event")
        }

        NDKLogger.log(.debug, category: .wallet, "Nutzap recipient tag: \(recipientTag[1])")

        // Get mint URLs from u tags
        let mintURLs = event.tags
            .filter { $0.count >= 2 && $0[0] == "u" }
            .map { $0[1] }

        NDKLogger.log(.debug, category: .wallet, "Mint URLs in nutzap: \(mintURLs)")

        guard !mintURLs.isEmpty else {
            NDKLogger.log(.error, category: .wallet, "No mint URLs in nutzap")
            throw NutzapRedemptionError.invalidProofs(reason: "No mint URLs in nutzap event")
        }

        // Extract proofs from proof tags
        let proofTags = event.tags.filter { $0.count >= 2 && $0[0] == NostrConstants.TagName.proof }
        guard !proofTags.isEmpty else {
            NDKLogger.log(.error, category: .wallet, "No proofs in nutzap")
            throw NutzapRedemptionError.invalidProofs(reason: "No proofs in nutzap event")
        }

        NDKLogger.log(.debug, category: .wallet, "Found \(proofTags.count) proof tags in nutzap")

        var allProofs: [CashuSwift.Proof] = []
        var invalidP2PKError: String?

        for proofTag in proofTags {
            guard let proofData = proofTag[1].data(using: .utf8),
                  let proof = try? JSONCoding.decode(CashuSwift.Proof.self, from: proofData) else {
                NDKLogger.log(.error, category: .wallet, "\(ErrorMessageConstants.failedTo("decode proof from tag")): \(proofTag[1])")
                continue
            }

            // Extract P2PK data from proof secret for logging
            var p2pkInfo = "none"
            if let secretData = proof.secret.data(using: .utf8),
               let secret = try? JSONSerialization.jsonObject(with: secretData, options: []) as? [[String: Any]] {
                for condition in secret {
                    if condition[NostrConstants.JSONField.kind] as? String == "P2PK",
                       let data = condition["data"] as? String {
                        p2pkInfo = data

                        // Validate P2PK pubkey format (compressed secp256k1 keys)
                        if data.count != 66 || (!data.hasPrefix("02") && !data.hasPrefix("03")) {
                            let errorMessage = "\(ErrorMessageConstants.invalid("P2PK pubkey format")): \(data) (must be 66 hex chars starting with 02 or 03)"
                            NDKLogger.log(.error, category: .wallet, errorMessage)
                            invalidP2PKError = errorMessage
                        }
                        break
                    }
                }
            }

            NDKLogger.log(.debug, category: .wallet, "Decoded proof: amount=\(proof.amount), C=\(proof.C), P2PK=\(p2pkInfo)")
            allProofs.append(proof)
        }

        // If we found invalid P2PK pubkeys, throw the error
        if let errorMessage = invalidP2PKError {
            throw NutzapRedemptionError.invalidProofs(reason: errorMessage)
        }

        var totalReceived: Int64 = 0
        var redeemedProofs: [CashuSwift.Proof] = []

        // Filter proofs locked to us
        let ourProofs = CashuHelpers.filterProofsLockedTo(proofs: allProofs, pubkey: ourPubkeyHex)

        NDKLogger.log(.debug, category: .wallet, "Total proofs: \(allProofs.count), Proofs locked to us: \(ourProofs.count)")

        guard !ourProofs.isEmpty else {
            NDKLogger.log(.debug, category: .wallet, "No proofs locked to our P2PK pubkey (\(ourPubkeyHex)) in nutzap")
            // Extract expected pubkey from the first proof's secret
            var expectedPubkey = "unknown"
            if let firstProof = allProofs.first,
               let secretData = firstProof.secret.data(using: .utf8),
               let secret = try? JSONSerialization.jsonObject(with: secretData, options: []) as? [[String: Any]],
               let p2pkCondition = secret.first(where: { $0[NostrConstants.JSONField.kind] as? String == "P2PK" }),
               let data = p2pkCondition["data"] as? String {
                expectedPubkey = data
            }
            throw NutzapRedemptionError.p2pkLockedToUnknownKey(expectedPubkey: expectedPubkey, actualPubkey: ourPubkeyHex)
        }

        // Process proofs by mint
        for mintURL in mintURLs {
            // Load mint dynamically
            guard let mintUrl = URL(string: mintURL) else {
                NDKLogger.log(.error, category: .general, "\(ErrorMessageConstants.invalid("mint URL in nutzap")): \(mintURL)")
                continue
            }

            let mint: CashuSwift.Mint
            do {
                mint = try await wallet.mints.loadMint(url: mintUrl)
            } catch {
                NDKLogger.log(.error, category: .general, "\(ErrorMessageConstants.failedTo("load mint \(mintURL) for nutzap")): \(error)")
                continue
            }

            // Find proofs for this mint
            let mintProofs = ourProofs.filter { proof in
                mint.keysets.contains { $0.keysetID == proof.keysetID }
            }

            guard !mintProofs.isEmpty else { continue }

            // Redeem the P2PK-locked proofs
            let lockedToken = CashuSwift.Token(
                proofs: [mintURL: mintProofs],
                unit: "sat"
            )
            let (unlockedProofs, _, _) = try await CashuSwift.receive(
                token: lockedToken,
                of: mint,
                seed: nil,
                privateKey: privateKey
            )

            // Add unlocked proofs to our wallet
            for proof in unlockedProofs {
                await proofStateManager.addProof(proof, mint: mintURL)
                totalReceived += Int64(proof.amount)
            }

            redeemedProofs.append(contentsOf: unlockedProofs)
        }

        guard totalReceived > 0 else {
            throw NutzapRedemptionError.insufficientAmount(expected: 1, actual: 0)
        }

        // Update wallet state
        // Group by mint since we may have redeemed from multiple mints
        var proofsByMint: [String: [CashuSwift.Proof]] = [:]
        for proof in redeemedProofs {
            if let proofMint = mints.first(where: { _, mint in
                mint.keysets.contains { $0.keysetID == proof.keysetID }
            }) {
                proofsByMint[proofMint.key, default: []].append(proof)
            }
        }

        // Update state for each mint
        for (mintURL, proofs) in proofsByMint {
            let stateChange = WalletStateChange(
                store: proofs,
                destroy: [],
                mint: mintURL,
                memo: "Receive nutzap"
            )
            _ = try await wallet.update(stateChange: stateChange)
        }

        // Create spending history for received nutzap
        // The comment is in the content field per NIP-61
        let nutzapComment = event.content.nilIfEmpty

        try await eventManager.createSpendingHistoryEvent(
            direction: .in,
            amount: totalReceived,
            memo: nutzapComment ?? "Nutzap received",
            destroyedEventIds: nil,
            createdEventIds: nil,
            redeemedEventId: event.id,
            signer: signer
        )

        // Mark the nutzap as redeemed
        await eventManager.markNutzapRedeemed(event.id, proofsCount: redeemedProofs.count)

        // Emit nutzap received notification
        await emitNutzapReceived(event: event, amount: totalReceived)

        return NutzapRedemptionResult(
            success: true,
            proofsRedeemed: redeemedProofs,
            error: nil,
            amount: totalReceived
        )
    }

    // MARK: - Private Helper Functions

    private static func lockProofsForRecipient(
        proofs: [CashuSwift.Proof],
        amount: Int64,
        recipientPubkey: String,
        mint: CashuSwift.Mint,
        mintURL: String
    ) async throws -> (proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]?) {
        // Use CashuSwift's send function with P2PK locking
        let (token, changeProofs, _) = try await CashuSwift.send(
            inputs: proofs,
            mint: mint,
            amount: Int(amount),
            seed: nil,
            memo: nil,
            lockToPublicKey: recipientPubkey
        )

        // Get the locked proofs from the token
        guard let lockedProofs = token.proofsByMint[mintURL] else {
            throw NDKError.invalidProof("No proofs in created token")
        }

        return (proofs: lockedProofs, change: changeProofs)
    }


    private static func emitNutzapReceived(event: NDKEvent, amount: Int64) async {
        // Emit notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: .nutzapReceived,
                object: nil,
                userInfo: [
                    "event": event,
                    NostrConstants.JSONField.amount: amount
                ]
            )
        }
    }
}

// MARK: - Error Mapping

extension Nutzap {
    /// Map CashuSwift and other errors to NutzapRedemptionError
    public static func mapToRedemptionError(_ error: Error) -> NutzapRedemptionError {
        switch error {
        case let cashuError as CashuError:
            switch cashuError {
            case .networkError:
                return .networkError("Network error occurred")
            case .cryptoError:
                return .dleqVerificationFailed
            case .quoteNotPaid:
                return .invalidProofs(reason: "Quote not paid")
            case .blindedMessageAlreadySigned:
                return .alreadySpent(proofIds: [])
            case .alreadySpent:
                return .alreadySpent(proofIds: [])
            case .transactionUnbalanced:
                return .invalidProofs(reason: "Transaction unbalanced")
            case .invalidToken:
                return .invalidProofs(reason: ErrorMessageConstants.invalid("token format"))
            case .tokenEncoding(let message):
                return .invalidProofs(reason: "Token encoding error: \(message)")
            case .tokenDecoding(let message):
                return .invalidProofs(reason: "Token decoding error: \(message)")
            case .unsupportedToken(let message):
                return .invalidProofs(reason: "Unsupported token: \(message)")
            case .inputError(let message):
                return .invalidProofs(reason: "Input error: \(message)")
            case .insufficientInputs(let message):
                return .invalidProofs(reason: "Insufficient inputs: \(message)")
            case .unitIsNotSupported(let message):
                return .invalidProofs(reason: "Unit not supported: \(message)")
            case .keysetInactive:
                return .invalidProofs(reason: "Keyset inactive")
            case .amountOutsideOfLimitRange:
                return .invalidProofs(reason: "Amount outside of limit range")
            case .proofsAlreadyIssuedForQuote:
                return .alreadySpent(proofIds: [])
            case .mintingDisabled:
                return .temporaryMintError("Minting disabled")
            case .typeMismatch(let message):
                return .invalidProofs(reason: "Type mismatch: \(message)")
            case .preferredDistributionMismatch(let message):
                return .invalidProofs(reason: "Distribution mismatch: \(message)")
            case .noActiveKeysetForUnit(let message):
                return .invalidProofs(reason: "No active keyset for unit: \(message)")
            case .unitError(let message):
                return .invalidProofs(reason: "Unit error: \(message)")
            case .invalidAmount:
                return .invalidProofs(reason: ErrorMessageConstants.invalid("amount"))
            case .missingRequestDetail(let message):
                return .invalidProofs(reason: "Missing request detail: \(message)")
            case .restoreError(let message):
                return .invalidProofs(reason: "Restore error: \(message)")
            case .feeCalculationError(let message):
                return .invalidProofs(reason: "Fee calculation error: \(message)")
            case .partiallySpentToken:
                return .alreadySpent(proofIds: [])
            case .bolt11InvalidInvoiceError(let message):
                return .invalidProofs(reason: "Invalid invoice: \(message)")
            case .quoteIsPending:
                return .temporaryMintError("Quote is pending")
            case .invoiceAlreadyPaid:
                return .alreadySpent(proofIds: [])
            case .quoteIsExpired:
                return .temporaryMintError("Quote expired")
            case .unknownError(let message):
                return .unknownError(message)
            case .spendingConditionError(let message):
                return .invalidProofs(reason: "Spending condition error: \(message)")
            case .invalidKey(let message):
                return .invalidProofs(reason: "Invalid key: \(message)")
            case .p2pkSigningError(let message):
                return .invalidProofs(reason: "P2PK signing error: \(message)")
            case .invalidSplit(let message):
                return .invalidProofs(reason: "Invalid split: \(message)")
            }
        case let ndkError as NDKError:
            switch ndkError {
            case .connectionFailed(let relay, let message, _):
                return .networkError("Connection to \(relay) failed: \(message)")
            case .insufficientBalance(let amount):
                return .insufficientAmount(expected: amount ?? 0, actual: 0)
            case .walletError(let message):
                // Check if it's an invalid proof error
                if message.contains("Invalid proof:") {
                    return .invalidProofs(reason: message)
                }
                return .unknownError(message)
            default:
                return .unknownError(ndkError.localizedDescription)
            }
        case let urlError as URLError:
            return .networkError("Network error: \(urlError.localizedDescription)")
        default:
            return .unknownError(error.localizedDescription)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let nutzapReceived = Notification.Name("NIP60Wallet.nutzapReceived")
}