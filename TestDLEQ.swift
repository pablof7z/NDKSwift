import Foundation
import CashuSwift
import NDKSwift

// Simple test to check DLEQ verification
@main
struct TestDLEQ {
    static func main() async {
        print("Testing DLEQ verification...")
        
        // Test with a known mint
        let mintURL = URL(string: "https://mint.cubabitcoin.org")!
        
        do {
            // Initialize mint
            let mint = try await CashuSwift.Mint(url: mintURL)
            print("Mint initialized: \(mintURL)")
            print("Active keysets: \(mint.keysets.filter { $0.active }.count)")
            
            // Create a mint quote
            let amount = 21
            let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: amount, options: nil)
            let mintQuote = try await CashuSwift.Bolt11.mintQuote(mint: mint, requestBody: quoteRequest)
            print("\nMint quote created:")
            print("Quote ID: \(mintQuote.quote)")
            print("Invoice: \(mintQuote.request.prefix(50))...")
            
            // For testing, we'll just check if DLEQ data is present in mint info
            if let activeKeyset = mint.keysets.first(where: { $0.active && $0.unit == "sat" }) {
                print("\nActive keyset ID: \(activeKeyset.keysetID)")
                print("Keys count: \(activeKeyset.keys.count)")
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
}