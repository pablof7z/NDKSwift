import CashuSwift
import Foundation
import NDKSwiftCore

// MARK: - Helper Extensions for NDKCashuSpendingHistory

public extension NDKCashuSpendingHistory {
    /// Extract decrypted spending history data
    func decryptedHistoryData(signer: NDKSigner) async throws -> HistoryData {
        // Decrypt the content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )

        // Parse tags from decrypted content
        guard let tagsData = decryptedContent.data(using: .utf8),
              let tags = try? JSONCoding.decode([[String]].self, from: tagsData)
        else {
            throw NDKError.invalidContent("Failed to parse history event tags")
        }

        var direction: SpendingDirection?
        var amount: Int64?
        var memo: String?
        var mint: String?
        var token: String?
        var createdEventIds: [String] = []
        var destroyedEventIds: [String] = []

        // Extract data from encrypted tags
        for tag in tags {
            guard tag.count >= 2 else { continue }
            switch tag[0] {
            case "direction":
                direction = SpendingDirection(rawValue: tag[1])
            case "amount":
                amount = Int64(tag[1])
            case "memo":
                memo = tag[1]
            case "mint":
                mint = tag[1]
            case "token":
                token = tag[1]
            case "description": // Also check for description tag (legacy)
                if memo == nil {
                    memo = tag[1]
                }
            case "e":
                if tag.count >= 4 {
                    switch tag[3] {
                    case "created":
                        createdEventIds.append(tag[1])
                    case "destroyed":
                        destroyedEventIds.append(tag[1])
                    default:
                        break
                    }
                }
            default:
                break
            }
        }

        // Extract data from clear tags
        var redeemedEventId: String?
        var nutzapSender: String?

        for tag in event.tags {
            if tag.count >= 4 && tag[0] == "e" && tag[3] == "redeemed" {
                redeemedEventId = tag[1]
                if tag.count >= 5 {
                    nutzapSender = tag[4]
                }
            }
        }

        return HistoryData(
            direction: direction,
            amount: amount ?? 0,
            memo: memo,
            mint: mint,
            token: token,
            createdEventIds: createdEventIds,
            destroyedEventIds: destroyedEventIds,
            redeemedEventId: redeemedEventId,
            nutzapSender: nutzapSender
        )
    }

    /// Structure containing decrypted history data
    struct HistoryData {
        public let direction: SpendingDirection?
        public let amount: Int64
        public let memo: String?
        public let mint: String?
        public let token: String?
        public let createdEventIds: [String]
        public let destroyedEventIds: [String]
        public let redeemedEventId: String?
        public let nutzapSender: String?

        /// Determine transaction type based on the history data
        public var transactionType: TransactionType {
            // Nutzap is identified by redeemed event
            if redeemedEventId != nil {
                return .nutzap
            }

            // Otherwise determine by direction
            guard let dir = direction else { return .unknown }

            switch dir {
            case .in:
                // Check if it's a mint (from Lightning) or receive (from ecash)
                if memo?.lowercased().contains("lightning") == true ||
                    memo?.lowercased().contains("deposit") == true
                {
                    return .mint
                }
                return .receive
            case .out:
                // Check if it's a melt (to Lightning) or send (ecash)
                if memo?.lowercased().contains("lightning") == true ||
                    memo?.lowercased().contains("payment") == true
                {
                    return .melt
                }
                return .send
            }
        }

        /// Get a default memo if none is provided
        public var defaultMemo: String {
            if let memo = memo, !memo.isEmpty {
                return memo
            }

            switch transactionType {
            case .mint:
                return StringConstants.Transactions.lightningDeposit
            case .melt:
                return StringConstants.Transactions.lightningPayment
            case .send:
                return "Sent ecash"
            case .receive:
                return "Received ecash"
            case .nutzap:
                if let sender = nutzapSender {
                    return "Nutzap from \(sender.prefix(8))..."
                }
                return "Nutzap"
            case .unknown:
                return "Unknown transaction"
            }
        }
    }

    enum TransactionType {
        case mint // Lightning -> ecash
        case melt // ecash -> Lightning
        case send // ecash send
        case receive // ecash receive
        case nutzap // nutzap
        case unknown
    }
}
