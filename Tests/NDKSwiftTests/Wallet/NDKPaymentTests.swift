import XCTest
@testable import NDKSwift

final class NDKPaymentTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        ndk = NDK()
        let privateKey = Crypto.generatePrivateKey()
        signer = try! NDKPrivateKeySigner(privateKey: privateKey)
        ndk.signer = signer
    }
    
    func testPaymentRequestCreation() throws {
        let recipient = ndk.getUser("82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
        let request = NDKPaymentRequest(
            recipient: recipient,
            amount: 1000,
            comment: "Test payment"
        )
        
        XCTAssertEqual(request.amount, 1000)
        XCTAssertEqual(request.comment, "Test payment")
        XCTAssertEqual(request.recipient.pubkey, recipient.pubkey)
        XCTAssertEqual(request.unit, "sat")
    }
    
    func testNutzapCreation() async throws {
        var nutzap = NDKNutzap(ndk: ndk)
        
        // Set basic properties
        nutzap.mint = "https://mint.example.com"
        nutzap.comment = "Test nutzap"
        nutzap.setRecipient("82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
        
        // Add proofs
        nutzap.proofs = [
            CashuProof(
                id: "test-keyset",
                amount: 100,
                secret: "test-secret",
                C: "test-signature"
            )
        ]
        
        // Sign the event
        try await nutzap.sign()
        
        // Verify properties
        XCTAssertEqual(nutzap.event.kind, EventKind.nutzap)
        XCTAssertEqual(nutzap.mint, "https://mint.example.com")
        XCTAssertEqual(nutzap.comment, "Test nutzap")
        XCTAssertEqual(nutzap.recipientPubkey, "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
        XCTAssertEqual(nutzap.totalAmount, 100)
        XCTAssertNotNil(nutzap.event.sig)
        XCTAssertTrue(nutzap.event.tags.contains { $0.first == "alt" })
    }
    
    func testCashuProofSerialization() throws {
        let proof = CashuProof(
            id: "test-id",
            amount: 500,
            secret: "test-secret",
            C: "test-c"
        )
        
        let data = try JSONEncoder().encode(proof)
        let decoded = try JSONDecoder().decode(CashuProof.self, from: data)
        
        XCTAssertEqual(decoded.id, proof.id)
        XCTAssertEqual(decoded.amount, proof.amount)
        XCTAssertEqual(decoded.secret, proof.secret)
        XCTAssertEqual(decoded.C, proof.C)
    }
    
    func testMintListEvent() async throws {
        var mintList = NDKCashuMintList(ndk: ndk)
        
        // Add mints
        mintList.addMint("https://mint1.example.com")
        mintList.addMint("https://mint2.example.com")
        
        // Add relays
        mintList.addRelay("wss://relay1.example.com")
        mintList.addRelay("wss://relay2.example.com")
        
        // Enable P2PK
        mintList.setP2PK(true)
        
        // Sign
        try await mintList.sign()
        
        // Verify
        XCTAssertEqual(mintList.event.kind, EventKind.cashuMintList)
        XCTAssertEqual(mintList.mints.count, 2)
        XCTAssertTrue(mintList.mints.contains("https://mint1.example.com"))
        XCTAssertTrue(mintList.mints.contains("https://mint2.example.com"))
        XCTAssertEqual(mintList.relays.count, 2)
        XCTAssertTrue(mintList.p2pk)
        XCTAssertNotNil(mintList.event.sig)
    }
    
    func testPaymentMethodDetection() async throws {
        // Create a user with Lightning support
        let userProfile = NDKUserProfile(
            name: "Test User",
            lud16: "testuser@getalby.com"
        )
        
        // Mock the profile fetch
        let user = ndk.getUser("test-pubkey")
        user.updateProfile(userProfile)
        
        // In a real test, we would mock the fetchProfile method
        // For now, we just verify the profile is set
        XCTAssertNotNil(user.profile?.lud16)
    }
    
    func testWalletConfiguration() {
        var lightningPaymentCalled = false
        var cashuPaymentCalled = false
        
        ndk.walletConfig = NDKWalletConfig(
            lnPay: { request, invoice in
                lightningPaymentCalled = true
                return nil
            },
            cashuPay: { request in
                cashuPaymentCalled = true
                return nil
            },
            nutzapAsFallback: true
        )
        
        XCTAssertNotNil(ndk.walletConfig)
        XCTAssertNotNil(ndk.paymentRouter)
        XCTAssertTrue(ndk.walletConfig!.nutzapAsFallback)
    }
    
    func testNutzapFromEvent() {
        let event = NDKEvent(content: "", tags: [])
        event.ndk = ndk
        event.kind = EventKind.nutzap
        event.tags = [
            ["proof", #"{"id":"test","amount":100,"secret":"test","C":"test"}"#],
            ["u", "https://mint.example.com"],
            ["p", "recipient-pubkey"]
        ]
        event.content = "Test comment"
        
        let nutzap = NDKNutzap.from(event)
        
        XCTAssertNotNil(nutzap)
        XCTAssertEqual(nutzap?.proofs.count, 1)
        XCTAssertEqual(nutzap?.proofs.first?.amount, 100)
        XCTAssertEqual(nutzap?.mint, "https://mint.example.com")
        XCTAssertEqual(nutzap?.recipientPubkey, "recipient-pubkey")
        XCTAssertEqual(nutzap?.comment, "Test comment")
    }
    
    func testPaymentConfirmationTypes() {
        let lightningConfirmation = NDKLightningPaymentConfirmation(
            amount: 1000,
            recipient: "recipient-pubkey",
            timestamp: Date(),
            preimage: "test-preimage",
            paymentRequest: "lnbc..."
        )
        
        XCTAssertEqual(lightningConfirmation.amount, 1000)
        XCTAssertEqual(lightningConfirmation.preimage, "test-preimage")
        
        let cashuConfirmation = NDKCashuPaymentConfirmation(
            amount: 500,
            recipient: "recipient-pubkey",
            timestamp: Date(),
            nutzap: nil
        )
        
        XCTAssertEqual(cashuConfirmation.amount, 500)
        XCTAssertNil(cashuConfirmation.nutzap)
    }
}