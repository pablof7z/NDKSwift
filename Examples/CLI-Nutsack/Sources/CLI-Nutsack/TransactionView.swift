import Foundation
import NDKSwift

struct TransactionView {
    static func showHistory(ndk: NDK, wallet: NDKCashuWallet) async throws {
        guard let signer = ndk.signer else {
            print("❌ No signer available")
            return
        }
        let pubkey = try await signer.pubkey
        
        print("📜 Transaction History")
        print("=".repeated(80))
        print("Fetching transaction history...\n")
        
        // Fetch spending history events (kind 7376)
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [7376]
        )
        
        let events = try await ndk.fetchEvents(filter)
        
        if events.isEmpty {
            print("📭 No transaction history found")
            return
        }
        
        print("Found \(events.count) transactions\n")
        
        // Parse and sort transactions
        var transactions: [(date: Date, direction: String, amount: Int, type: String, description: String)] = []
        
        for event in events {
            // Decrypt content if possible
            if let signer = ndk.signer,
               !event.content.isEmpty,
               let decrypted = try? await signer.decrypt(
                   sender: NDKUser(pubkey: event.pubkey),
                   value: event.content,
                   scheme: .nip44
               ),
               let data = decrypted.data(using: String.Encoding.utf8),
               let tags = try? JSONDecoder().decode([[String]].self, from: data) {
                
                // Parse from decrypted tags
                let direction = tags.first(where: { $0.first == "direction" })?.dropFirst().first ?? "?"
                let amountStr = tags.first(where: { $0.first == "amount" })?.dropFirst().first ?? "0"
                let amount = Int(amountStr) ?? 0
                let description = tags.first(where: { $0.first == "description" })?.dropFirst().joined(separator: " ") ?? ""
                let txType = event.tags.first(where: { $0.first == "type" })?.dropFirst().first ?? "cashu"
                
                transactions.append((
                    date: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                    direction: direction,
                    amount: amount,
                    type: txType,
                    description: description
                ))
            }
        }
        
        // Sort by date (newest first)
        transactions.sort { $0.date > $1.date }
        
        // Render table
        let headers = ["Date", "Type", "Amount", "Description"]
        var rows: [[String]] = []
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for tx in transactions {
            let directionIcon = tx.direction == "in" ? "↓" : tx.direction == "out" ? "↑" : "↔"
            let amountStr = tx.direction == "out" ? "-\(tx.amount)" : "+\(tx.amount)"
            
            rows.append([
                dateFormatter.string(from: tx.date),
                "\(directionIcon) \(tx.type)",
                "\(amountStr) sats",
                tx.description.truncated(to: 40)
            ])
        }
        
        TableRenderer.render(headers: headers, rows: rows)
        
        // Summary
        let totalIn = transactions.filter { $0.direction == "in" }.reduce(0) { $0 + $1.amount }
        let totalOut = transactions.filter { $0.direction == "out" }.reduce(0) { $0 + $1.amount }
        
        print("\n" + "─".repeated(80))
        print("📊 Summary:")
        print("   Total received: \(totalIn) sats")
        print("   Total sent: \(totalOut) sats")
        print("   Net: \(totalIn - totalOut) sats")
        
        // Current balance
        let currentBalance = try await wallet.getBalance()
        print("   Current balance: \(currentBalance) sats")
    }
    
    static func showTransactionDetails(ndk: NDK, event: NDKEvent) async throws {
        clearScreen()
        print("📋 Transaction Details")
        print("=".repeated(50))
        
        let date = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Parse transaction details
        let direction = event.tags.first(where: { $0.first == "direction" })?.dropFirst().first ?? "?"
        let amountStr = event.tags.first(where: { $0.first == "amount" })?.dropFirst().first ?? "0"
        let amount = Int(amountStr) ?? 0
        let mint = event.tags.first(where: { $0.first == "mint" })?.dropFirst().first ?? "Unknown"
        let description = event.tags.first(where: { $0.first == "description" })?.dropFirst().joined(separator: " ") ?? ""
        
        let directionIcon = direction == "in" ? "↓" : direction == "out" ? "↑" : "?"
        let directionColor = direction == "in" ? "🟢" : direction == "out" ? "🔴" : "⚪"
        
        print("\(directionColor) Direction: \(directionIcon) \(direction.uppercased())")
        print("💰 Amount: \(amount) sats")
        print("📅 Date: \(dateFormatter.string(from: date))")
        print("📝 Description: \(description)")
        print("🏦 Mint: \(mint)")
        
        // Check for nutzap redemption
        if let redeemedTag = event.tags.first(where: { $0.first == "e" && $0.contains("redeemed") }) {
            print("\n🎁 Type: Nutzap redemption")
            
            if let nutzapId = redeemedTag.dropFirst().first {
                // Try to fetch the nutzap event
                if let nutzapEvent = try? await ndk.fetchEvent(nutzapId) {
                    let sender = NDKUser(pubkey: nutzapEvent.pubkey)
                    print("👤 From: \(sender.npub)")
                }
            }
        }
        
        print("\n" + "=".repeated(50))
    }
}

extension String {
    func truncated(to length: Int) -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length - 3)) + "..."
    }
}