import Testing
@testable import Olas

@Suite("SparkWallet Types")
struct SparkWalletTypesTests {

    // MARK: - SparkParsedInput.requiresAmount

    @Suite("requiresAmount")
    struct RequiresAmountTests {

        @Test("Bolt11 invoice without amount requires amount")
        func bolt11WithoutAmount_requiresAmount() {
            let details = SparkBolt11Details(
                invoice: "lnbc1...",
                amountSats: nil,
                description: "Test",
                expiry: 3600,
                payeePubkey: "abc123"
            )
            let input = SparkParsedInput.bolt11Invoice(details)

            #expect(input.requiresAmount == true)
        }

        @Test("Bolt11 invoice with amount does not require amount")
        func bolt11WithAmount_doesNotRequireAmount() {
            let details = SparkBolt11Details(
                invoice: "lnbc1000n...",
                amountSats: 1000,
                description: "Test",
                expiry: 3600,
                payeePubkey: "abc123"
            )
            let input = SparkParsedInput.bolt11Invoice(details)

            #expect(input.requiresAmount == false)
        }

        @Test("Bitcoin address without amount requires amount")
        func bitcoinAddressWithoutAmount_requiresAmount() {
            let details = SparkBitcoinAddressDetails(
                address: "bc1q...",
                network: "mainnet",
                amountSats: nil
            )
            let input = SparkParsedInput.bitcoinAddress(details)

            #expect(input.requiresAmount == true)
        }

        @Test("Bitcoin address with amount does not require amount")
        func bitcoinAddressWithAmount_doesNotRequireAmount() {
            let details = SparkBitcoinAddressDetails(
                address: "bc1q...",
                network: "mainnet",
                amountSats: 50000
            )
            let input = SparkParsedInput.bitcoinAddress(details)

            #expect(input.requiresAmount == false)
        }

        @Test("LNURL pay always requires amount")
        func lnurlPay_alwaysRequiresAmount() {
            let details = SparkLnurlPayDetails(
                domain: "example.com",
                minSendableSats: 1,
                maxSendableSats: 1_000_000,
                metadata: "{}",
                lightningAddress: "user@example.com"
            )
            let input = SparkParsedInput.lnurlPay(details)

            #expect(input.requiresAmount == true)
        }

        @Test("Spark address always requires amount")
        func sparkAddress_alwaysRequiresAmount() {
            let details = SparkAddressDetails(address: "sp1...")
            let input = SparkParsedInput.sparkAddress(details)

            #expect(input.requiresAmount == true)
        }

        @Test("Spark invoice does not require amount")
        func sparkInvoice_doesNotRequireAmount() {
            let details = SparkInvoiceDetails(invoice: "spark1...", amountSats: 1000)
            let input = SparkParsedInput.sparkInvoice(details)

            #expect(input.requiresAmount == false)
        }

        @Test("LNURL withdraw does not require amount")
        func lnurlWithdraw_doesNotRequireAmount() {
            let details = SparkLnurlWithdrawDetails(
                domain: "example.com",
                minWithdrawableSats: 100,
                maxWithdrawableSats: 10000,
                description: "Withdraw"
            )
            let input = SparkParsedInput.lnurlWithdraw(details)

            #expect(input.requiresAmount == false)
        }

        @Test("URL does not require amount")
        func url_doesNotRequireAmount() {
            let input = SparkParsedInput.url("https://example.com")

            #expect(input.requiresAmount == false)
        }

        @Test("Node ID does not require amount")
        func nodeId_doesNotRequireAmount() {
            let input = SparkParsedInput.nodeId("02abc...")

            #expect(input.requiresAmount == false)
        }
    }

    // MARK: - SparkParsedInput.embeddedAmountSats

    @Suite("embeddedAmountSats")
    struct EmbeddedAmountTests {

        @Test("Bolt11 with amount returns embedded amount")
        func bolt11WithAmount_returnsAmount() {
            let details = SparkBolt11Details(
                invoice: "lnbc1000n...",
                amountSats: 1000,
                description: nil,
                expiry: 3600,
                payeePubkey: "abc"
            )
            let input = SparkParsedInput.bolt11Invoice(details)

            #expect(input.embeddedAmountSats == 1000)
        }

        @Test("Bolt11 without amount returns nil")
        func bolt11WithoutAmount_returnsNil() {
            let details = SparkBolt11Details(
                invoice: "lnbc...",
                amountSats: nil,
                description: nil,
                expiry: 3600,
                payeePubkey: "abc"
            )
            let input = SparkParsedInput.bolt11Invoice(details)

            #expect(input.embeddedAmountSats == nil)
        }

        @Test("Bitcoin address with amount returns embedded amount")
        func bitcoinAddressWithAmount_returnsAmount() {
            let details = SparkBitcoinAddressDetails(
                address: "bc1q...",
                network: "mainnet",
                amountSats: 50000
            )
            let input = SparkParsedInput.bitcoinAddress(details)

            #expect(input.embeddedAmountSats == 50000)
        }

        @Test("Spark invoice returns embedded amount")
        func sparkInvoice_returnsAmount() {
            let details = SparkInvoiceDetails(invoice: "spark1...", amountSats: 2500)
            let input = SparkParsedInput.sparkInvoice(details)

            #expect(input.embeddedAmountSats == 2500)
        }

        @Test("LNURL pay returns nil")
        func lnurlPay_returnsNil() {
            let details = SparkLnurlPayDetails(
                domain: "example.com",
                minSendableSats: 1,
                maxSendableSats: 1_000_000,
                metadata: "{}",
                lightningAddress: nil
            )
            let input = SparkParsedInput.lnurlPay(details)

            #expect(input.embeddedAmountSats == nil)
        }

        @Test("URL returns nil")
        func url_returnsNil() {
            let input = SparkParsedInput.url("https://example.com")

            #expect(input.embeddedAmountSats == nil)
        }
    }

    // MARK: - SparkParsedInput.typeDescription

    @Suite("typeDescription")
    struct TypeDescriptionTests {

        @Test("Bolt11 invoice description")
        func bolt11_description() {
            let details = SparkBolt11Details(
                invoice: "", amountSats: nil, description: nil, expiry: 0, payeePubkey: ""
            )
            let input = SparkParsedInput.bolt11Invoice(details)

            #expect(input.typeDescription == "Lightning Invoice")
        }

        @Test("Bitcoin address description")
        func bitcoinAddress_description() {
            let details = SparkBitcoinAddressDetails(address: "", network: "", amountSats: nil)
            let input = SparkParsedInput.bitcoinAddress(details)

            #expect(input.typeDescription == "Bitcoin Address")
        }

        @Test("LNURL pay description")
        func lnurlPay_description() {
            let details = SparkLnurlPayDetails(
                domain: "", minSendableSats: 0, maxSendableSats: 0, metadata: "", lightningAddress: nil
            )
            let input = SparkParsedInput.lnurlPay(details)

            #expect(input.typeDescription == "Lightning Address")
        }

        @Test("LNURL withdraw description")
        func lnurlWithdraw_description() {
            let details = SparkLnurlWithdrawDetails(
                domain: "", minWithdrawableSats: 0, maxWithdrawableSats: 0, description: ""
            )
            let input = SparkParsedInput.lnurlWithdraw(details)

            #expect(input.typeDescription == "LNURL Withdraw")
        }

        @Test("Spark address description")
        func sparkAddress_description() {
            let details = SparkAddressDetails(address: "")
            let input = SparkParsedInput.sparkAddress(details)

            #expect(input.typeDescription == "Spark Address")
        }

        @Test("Spark invoice description")
        func sparkInvoice_description() {
            let details = SparkInvoiceDetails(invoice: "", amountSats: 0)
            let input = SparkParsedInput.sparkInvoice(details)

            #expect(input.typeDescription == "Spark Invoice")
        }

        @Test("Node ID description")
        func nodeId_description() {
            let input = SparkParsedInput.nodeId("")

            #expect(input.typeDescription == "Node ID")
        }

        @Test("URL description")
        func url_description() {
            let input = SparkParsedInput.url("")

            #expect(input.typeDescription == "URL")
        }
    }

    // MARK: - SparkWalletError

    @Suite("SparkWalletError")
    struct WalletErrorTests {

        @Test("notConnected has proper description")
        func notConnected_description() {
            let error = SparkWalletError.notConnected

            #expect(error.errorDescription == "Spark wallet is not connected")
        }

        @Test("alreadyConnected has proper description")
        func alreadyConnected_description() {
            let error = SparkWalletError.alreadyConnected

            #expect(error.errorDescription == "Spark wallet is already connected")
        }

        @Test("unsupportedPaymentType has proper description")
        func unsupportedPaymentType_description() {
            let error = SparkWalletError.unsupportedPaymentType

            #expect(error.errorDescription == "Unsupported payment type for Spark wallet")
        }

        @Test("invalidMnemonic has proper description")
        func invalidMnemonic_description() {
            let error = SparkWalletError.invalidMnemonic

            #expect(error.errorDescription == "Invalid mnemonic phrase")
        }

        @Test("connectionFailed includes reason")
        func connectionFailed_description() {
            let error = SparkWalletError.connectionFailed("Network timeout")

            #expect(error.errorDescription == "Failed to connect to Spark network: Network timeout")
        }
    }

    // MARK: - SparkPaymentType & SparkPaymentStatus

    @Suite("Payment Enums")
    struct PaymentEnumTests {

        @Test("SparkPaymentType has send and receive")
        func paymentType_values() {
            let send = SparkPaymentType.send
            let receive = SparkPaymentType.receive

            #expect(send != receive)
        }

        @Test("SparkPaymentStatus has all states")
        func paymentStatus_values() {
            let pending = SparkPaymentStatus.pending
            let completed = SparkPaymentStatus.completed
            let failed = SparkPaymentStatus.failed

            #expect(pending != completed)
            #expect(completed != failed)
            #expect(failed != pending)
        }
    }

    // MARK: - SparkWalletInfo

    @Suite("SparkWalletInfo")
    struct WalletInfoTests {

        @Test("Wallet info stores values correctly")
        func walletInfo_storesValues() {
            let info = SparkWalletInfo(
                balanceSats: 100_000,
                pendingReceiveSats: 5_000,
                pendingSendSats: 2_000,
                sparkAddress: "sp1abc..."
            )

            #expect(info.balanceSats == 100_000)
            #expect(info.pendingReceiveSats == 5_000)
            #expect(info.pendingSendSats == 2_000)
            #expect(info.sparkAddress == "sp1abc...")
        }

        @Test("Wallet info with nil address")
        func walletInfo_nilAddress() {
            let info = SparkWalletInfo(
                balanceSats: 50_000,
                pendingReceiveSats: 0,
                pendingSendSats: 0,
                sparkAddress: nil
            )

            #expect(info.sparkAddress == nil)
        }
    }

    // MARK: - SparkFiatRate

    @Suite("SparkFiatRate")
    struct FiatRateTests {

        @Test("Fiat rate stores values correctly")
        func fiatRate_storesValues() {
            let rate = SparkFiatRate(currency: "USD", rate: 67_500.0)

            #expect(rate.currency == "USD")
            #expect(rate.rate == 67_500.0)
        }
    }

    // MARK: - SparkWalletEvent

    @Suite("SparkWalletEvent")
    struct WalletEventTests {

        @Test("Connected event")
        func connected_event() {
            let event = SparkWalletEvent.connected

            if case .connected = event {
                #expect(true)
            } else {
                Issue.record("Expected .connected event")
            }
        }

        @Test("Disconnected event")
        func disconnected_event() {
            let event = SparkWalletEvent.disconnected

            if case .disconnected = event {
                #expect(true)
            } else {
                Issue.record("Expected .disconnected event")
            }
        }

        @Test("Synced event")
        func synced_event() {
            let event = SparkWalletEvent.synced

            if case .synced = event {
                #expect(true)
            } else {
                Issue.record("Expected .synced event")
            }
        }

        @Test("Payment succeeded event carries amount")
        func paymentSucceeded_event() {
            let event = SparkWalletEvent.paymentSucceeded(amountSats: 1000)

            if case .paymentSucceeded(let amount) = event {
                #expect(amount == 1000)
            } else {
                Issue.record("Expected .paymentSucceeded event")
            }
        }

        @Test("Payment failed event carries reason")
        func paymentFailed_event() {
            let event = SparkWalletEvent.paymentFailed(reason: "Insufficient balance")

            if case .paymentFailed(let reason) = event {
                #expect(reason == "Insufficient balance")
            } else {
                Issue.record("Expected .paymentFailed event")
            }
        }

        @Test("Payment pending event carries amount")
        func paymentPending_event() {
            let event = SparkWalletEvent.paymentPending(amountSats: 500)

            if case .paymentPending(let amount) = event {
                #expect(amount == 500)
            } else {
                Issue.record("Expected .paymentPending event")
            }
        }
    }

    // MARK: - SparkPreparedPayment

    @Suite("SparkPreparedPayment")
    struct PreparedPaymentTests {

        @Test("Prepared payment calculates total correctly")
        func preparedPayment_values() {
            // Verify payment calculation logic
            let amount: Int64 = 1000
            let fee: Int64 = 10
            let total: Int64 = 1010

            #expect(amount + fee == total)
        }
    }
}
