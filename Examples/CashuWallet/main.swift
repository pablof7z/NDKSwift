import Foundation
import NDKSwift
import CashuSwift

// Create NDK instance
let ndk = NDK()

// Create or load signer
let signer: NDKPrivateKeySigner
if CommandLine.arguments.count > 1 {
    signer = try NDKPrivateKeySigner(nsec: CommandLine.arguments[1])
} else {
    signer = try NDKPrivateKeySigner.generate()
    print("Generated new key: \(try signer.nsec)")
}

ndk.signer = signer

// Add relay and connect
ndk.addRelay("wss://relay.primal.net/")
await ndk.connect()

// Create wallet
let wallet = NDKCashuWallet(ndk: ndk)

// Try to load existing wallet, if it doesn't exist create a new one
do {
    try await wallet.load()
    print("Wallet loaded")
} catch {
    try await wallet.save()
    print("New wallet created")
}

// Main REPL loop
while true {
    print("\n[a] Show balance")
    print("[b] Deposit money")
    print("[q] Quit")
    print("\nChoice: ", terminator: "")
    
    guard let input = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) else {
        continue
    }
    
    switch input {
    case "a":
        let balance = try await wallet.getBalance()
        print("Balance: \(balance) sats")
        
    case "b":
        print("Amount to deposit (sats): ", terminator: "")
        guard let amountStr = readLine(),
              let amount = Int64(amountStr), 
              amount > 0 else {
            print("Invalid amount")
            continue
        }
        
        print("Mint URL [https://testnut.cashu.space]: ", terminator: "")
        let mintURL = readLine()?.trimmingCharacters(in: .whitespaces)
        let mint = mintURL?.isEmpty == false ? mintURL! : "https://testnut.cashu.space"
        
        do {
            let quote = try await wallet.requestMint(
                amount: amount,
                mintURL: mint,
                persistQuote: true
            )
            
            print("\nPay this invoice:")
            print(quote.invoice)
            print("\nMonitoring payment...")
            
            for try await status in wallet.monitorDeposit(quote: quote) {
                switch status {
                case .pending:
                    print(".", terminator: "")
                    fflush(stdout)
                case .minted:
                    print("\n✓ Payment received!")
                    break
                case .expired:
                    print("\n✗ Payment expired")
                    break
                case .cancelled:
                    print("\n✗ Payment cancelled") 
                    break
                }
            }
        } catch {
            print("Error: \(error)")
        }
        
    case "q":
        exit(0)
        
    default:
        print("Invalid choice")
    }
}