#!/usr/bin/env swift

import Foundation
import NDKSwift

// MARK: - NWC Demo

/// This example demonstrates how to use Nostr Wallet Connect (NWC) with NDKSwift
/// 
/// To use this demo:
/// 1. Get a NWC connection URI from your wallet provider (e.g., Alby, Mutiny, etc.)
/// 2. Replace the placeholder URI below with your actual connection URI
/// 3. Run: swift Examples/NWCDemo.swift
///
/// WARNING: This example uses a real wallet connection. Be careful with production wallets!

@main
struct NWCDemo {
    static func main() async {
        do {
            // Initialize NDK
            let ndk = NDK()
            
            // Example connection URI (replace with your actual URI)
            // Format: nostr+walletconnect://[wallet-pubkey]?relay=[relay-url]&secret=[client-secret]&lud16=[optional-lightning-address]
            let connectionURI = "nostr+walletconnect://YOUR_WALLET_PUBKEY?relay=wss%3A%2F%2Fyour-relay.com&secret=YOUR_SECRET_KEY"
            
            print("🔌 Connecting to NWC wallet...")
            
            // Create and connect to the wallet
            let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
            try await wallet.connect()
            
            print("✅ Connected to wallet!")
            
            // Get wallet info
            await printWalletInfo(wallet)
            
            // Check balance
            await checkBalance(wallet)
            
            // Create an invoice
            await createInvoice(wallet)
            
            // List recent transactions
            await listTransactions(wallet)
            
            // Demonstrate error handling
            await demonstrateErrorHandling(wallet)
            
            // Subscribe to notifications (if supported)
            await subscribeToNotifications(wallet)
            
        } catch let error as NDKError {
            print("❌ NDK Error: \(error)")
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func printWalletInfo(_ wallet: NDKNWCWallet) async {
        print("\n📊 Wallet Information:")
        print("====================")
        
        do {
            let info = try await wallet.getInfo()
            
            if let alias = info.alias {
                print("Alias: \(alias)")
            }
            
            if let network = info.network {
                print("Network: \(network)")
            }
            
            print("Supported methods: \(info.methods.joined(separator: ", "))")
            
            if let notifications = info.notifications {
                print("Supported notifications: \(notifications.joined(separator: ", "))")
            }
            
            // Check specific capabilities
            print("\nCapability checks:")
            for method in NWCMethod.allCases {
                let supported = await wallet.supportsMethod(method)
                print("  \(method.rawValue): \(supported ? "✅" : "❌")")
            }
            
        } catch {
            print("Failed to get wallet info: \(error)")
        }
    }
    
    static func checkBalance(_ wallet: NDKNWCWallet) async {
        print("\n💰 Balance Check:")
        print("================")
        
        do {
            let balance = try await wallet.getBalance()
            print("Balance: \(balance) sats")
            
            // Format with commas for readability
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let formatted = formatter.string(from: NSNumber(value: balance)) {
                print("Formatted: \(formatted) sats")
            }
            
        } catch {
            print("Failed to get balance: \(error)")
        }
    }
    
    static func createInvoice(_ wallet: NDKNWCWallet) async {
        print("\n🧾 Creating Invoice:")
        print("===================")
        
        do {
            // Create a 1000 sat invoice
            let amount: Int64 = 1000
            let description = "Test invoice from NDKSwift NWC demo"
            
            print("Creating invoice for \(amount) sats...")
            
            let invoice = try await wallet.makeInvoice(
                amount: amount,
                description: description,
                descriptionHash: nil,
                expiry: 3600 // 1 hour
            )
            
            if let bolt11 = invoice.invoice {
                print("Invoice created!")
                print("Amount: \(invoice.amount) sats")
                print("Payment hash: \(invoice.paymentHash)")
                print("Invoice: \(bolt11)")
                
                // Show QR code hint
                print("\n💡 Tip: You can generate a QR code for this invoice")
                print("   or paste it into a Lightning wallet to pay")
            }
            
        } catch {
            print("Failed to create invoice: \(error)")
        }
    }
    
    static func listTransactions(_ wallet: NDKNWCWallet) async {
        print("\n📜 Recent Transactions:")
        print("=====================")
        
        do {
            // Get last 10 transactions
            let transactions = try await wallet.listTransactions(
                from: nil,
                until: nil,
                limit: 10,
                offset: nil,
                unpaid: false,
                type: nil
            )
            
            if transactions.isEmpty {
                print("No transactions found")
            } else {
                print("Found \(transactions.count) transactions:")
                
                for (index, tx) in transactions.enumerated() {
                    print("\n\(index + 1). \(tx.type == .incoming ? "⬇️ Received" : "⬆️ Sent")")
                    print("   Amount: \(tx.amount) sats")
                    print("   Created: \(Date(timeIntervalSince1970: TimeInterval(tx.createdAt)))")
                    
                    if let settled = tx.settledAt {
                        print("   Settled: \(Date(timeIntervalSince1970: TimeInterval(settled)))")
                    }
                    
                    if let description = tx.description {
                        print("   Description: \(description)")
                    }
                    
                    if tx.preimage != nil {
                        print("   Status: ✅ Paid")
                    } else {
                        print("   Status: ⏳ Pending")
                    }
                }
            }
            
        } catch {
            print("Failed to list transactions: \(error)")
        }
    }
    
    static func demonstrateErrorHandling(_ wallet: NDKNWCWallet) async {
        print("\n🛡️ Error Handling Demo:")
        print("======================")
        
        // Try to pay an invalid invoice
        do {
            print("Attempting to pay invalid invoice...")
            _ = try await wallet.payInvoice("invalid_invoice_string")
        } catch let error as NDKError {
            print("Caught NDK error: \(error)")
        } catch {
            print("Caught unexpected error: \(error)")
        }
        
        // Try to lookup non-existent invoice
        do {
            print("\nLooking up non-existent invoice...")
            _ = try await wallet.lookupInvoice(
                paymentHash: "0000000000000000000000000000000000000000000000000000000000000000"
            )
        } catch NDKError.walletNotFound {
            print("Invoice not found (as expected)")
        } catch {
            print("Unexpected error: \(error)")
        }
    }
    
    static func subscribeToNotifications(_ wallet: NDKNWCWallet) async {
        print("\n🔔 Notification Subscription:")
        print("===========================")
        
        // Check if notifications are supported
        let supportsPaymentReceived = await wallet.supportsNotification(.paymentReceived)
        let supportsPaymentSent = await wallet.supportsNotification(.paymentSent)
        
        if !supportsPaymentReceived && !supportsPaymentSent {
            print("This wallet doesn't support notifications")
            return
        }
        
        print("Subscribing to notifications...")
        print("(This will run for 30 seconds)")
        
        // Subscribe to notifications
        let notifications = wallet.notifications()
        
        // Listen for 30 seconds
        let endTime = Date().addingTimeInterval(30)
        
        Task {
            for await notification in notifications {
                if Date() > endTime {
                    break
                }
                
                switch notification.notificationType {
                case NWCNotificationType.paymentReceived.rawValue:
                    print("\n💸 Payment Received!")
                    print("   Amount: \(notification.notification.amount) sats")
                    if let invoice = notification.notification.invoice {
                        print("   Invoice: \(invoice)")
                    }
                    
                case NWCNotificationType.paymentSent.rawValue:
                    print("\n💸 Payment Sent!")
                    print("   Amount: \(notification.notification.amount) sats")
                    if let fees = notification.notification.feesPaid {
                        print("   Fees: \(fees) sats")
                    }
                    
                default:
                    print("\n🔔 Unknown notification: \(notification.notificationType)")
                }
            }
        }
        
        // Wait for the notification task
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        print("\nNotification subscription ended")
    }
}

// MARK: - Advanced Usage Examples

extension NWCDemo {
    /// Example: Pay a Lightning invoice
    static func payInvoiceExample(_ wallet: NDKNWCWallet, invoice: String) async throws {
        print("Paying invoice...")
        
        let response = try await wallet.payInvoice(invoice)
        
        print("Payment successful!")
        print("Preimage: \(response.preimage)")
        if let fees = response.feesPaid {
            print("Fees paid: \(fees) sats")
        }
    }
    
    /// Example: Send a keysend payment
    static func keysendExample(_ wallet: NDKNWCWallet, recipientPubkey: String, amount: Int64) async throws {
        print("Sending keysend payment...")
        
        // Optional: Add custom TLV records
        let tlvRecords = [
            PayKeysendRequest.TLVRecord(
                type: 34349334, // Custom message type
                value: "48656c6c6f2066726f6d204e444b5377696674" // "Hello from NDKSwift" in hex
            )
        ]
        
        let response = try await wallet.payKeysend(
            amount: amount,
            pubkey: recipientPubkey,
            preimage: nil, // Let wallet generate
            tlvRecords: tlvRecords
        )
        
        print("Keysend successful!")
        print("Preimage: \(response.preimage)")
    }
    
    /// Example: Batch payment processing
    static func batchPaymentExample(_ wallet: NDKNWCWallet, invoices: [String]) async throws {
        print("Processing batch payment of \(invoices.count) invoices...")
        
        // Prepare payable invoices
        let payableInvoices = invoices.enumerated().map { index, invoice in
            MultiPayInvoiceRequest.PayableInvoice(
                id: "payment_\(index)",
                invoice: invoice,
                amount: nil // Use invoice amount
            )
        }
        
        // Send batch payment
        let results = try await wallet.multiPayInvoice(payableInvoices)
        
        // Process results
        var successCount = 0
        var failureCount = 0
        
        for (id, result) in results {
            switch result {
            case .success(let response):
                print("✅ \(id): Paid (preimage: \(response.preimage))")
                successCount += 1
            case .failure(let error):
                print("❌ \(id): Failed - \(error.message)")
                failureCount += 1
            }
        }
        
        print("\nBatch payment complete: \(successCount) succeeded, \(failureCount) failed")
    }
}
