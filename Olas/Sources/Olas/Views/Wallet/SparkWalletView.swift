import SwiftUI
import NDKSwift
import CoreImage.CIFilterBuiltins

public struct SparkWalletView: View {
    @ObservedObject var walletManager: SparkWalletManager

    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showSettings = false

    public init(walletManager: SparkWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        NavigationStack {
            Group {
                if walletManager.connectionStatus == .connected {
                    connectedView
                } else {
                    setupView
                }
            }
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if walletManager.connectionStatus == .connected {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateWallet) {
                CreateSparkWalletView(walletManager: walletManager)
            }
            .sheet(isPresented: $showImportWallet) {
                ImportSparkWalletView(walletManager: walletManager)
            }
            .sheet(isPresented: $showReceive) {
                ReceiveView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSend) {
                SendView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SparkWalletSettingsView(walletManager: walletManager)
                }
            }
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        ScrollView {
            VStack(spacing: 32) {
                balanceCard
                actionButtons
                recentTransactions
            }
            .padding()
        }
        .refreshable {
            await walletManager.sync()
        }
    }

    private var balanceCard: some View {
        VStack(spacing: 12) {
            Text("Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formatSats(walletManager.balance))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(OlasTheme.Colors.deepTeal)

            if let address = walletManager.lightningAddress {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(OlasTheme.Colors.zapGold)
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if walletManager.isLoading {
                ProgressView()
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button {
                showReceive = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32))
                    Text("Receive")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.deepTeal.opacity(0.1))
                .foregroundStyle(OlasTheme.Colors.deepTeal)
                .cornerRadius(16)
            }

            Button {
                showSend = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                    Text("Send")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.zapGold.opacity(0.1))
                .foregroundStyle(OlasTheme.Colors.zapGold)
                .cornerRadius(16)
            }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            if walletManager.payments.isEmpty {
                VStack(spacing: 8) {
                    Text("No recent transactions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(walletManager.payments) { payment in
                        PaymentRow(payment: payment)
                        if payment.id != walletManager.payments.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 80))
                .foregroundStyle(OlasTheme.Colors.zapGold)

            Text("Spark Wallet")
                .font(.title.bold())

            Text("Self-custodial Bitcoin Lightning wallet. Your keys, your coins.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if walletManager.connectionStatus == .connecting {
                ProgressView("Connecting...")
                    .padding()
            }

            if let error = walletManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    showCreateWallet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Wallet")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.deepTeal)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }

                Button {
                    showImportWallet = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Import Existing Wallet")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            Spacer()
        }
        .padding()
    }

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(formatted) sats"
    }
}

// MARK: - Payment Row

struct PaymentRow: View {
    let payment: SparkPayment

    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails = true
        } label: {
            HStack(spacing: 12) {
                // Icon
                Circle()
                    .fill(payment.type == .receive ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: payment.type == .receive ? "arrow.down" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(payment.type == .receive ? .green : .orange)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(payment.description ?? (payment.type == .receive ? "Received" : "Sent"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        PaymentStatusBadge(status: payment.status)
                        Text(payment.timestamp.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(payment.type == .receive ? "+" : "-")\(formatSats(payment.amountSats))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(payment.type == .receive ? .green : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            PaymentDetailView(payment: payment)
        }
    }

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") sats"
    }
}

// MARK: - Payment Status Badge

struct PaymentStatusBadge: View {
    let status: SparkPaymentStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .cornerRadius(4)
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Payment Detail View

struct PaymentDetailView: View {
    let payment: SparkPayment
    @Environment(\.dismiss) private var dismiss

    @State private var showFullDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Amount header
                    VStack(spacing: 8) {
                        Image(systemName: payment.type == .receive ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(payment.type == .receive ? .green : OlasTheme.Colors.zapGold)

                        Text("\(payment.type == .receive ? "+" : "-")\(formatSats(payment.amountSats))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        if payment.feeSats > 0 {
                            Text("Fee: \(formatSats(payment.feeSats))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        PaymentStatusBadge(status: payment.status)
                    }
                    .padding(.top, 20)

                    // Details section
                    VStack(alignment: .leading, spacing: 16) {
                        if let description = payment.description {
                            DetailRow(label: "Description", value: description)
                        }

                        DetailRow(label: "Date", value: payment.timestamp.formatted(date: .abbreviated, time: .shortened))

                        if let destination = payment.destination {
                            DetailRow(label: payment.type == .send ? "To" : "From", value: destination, isMonospace: true)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Technical details (expandable)
                    DisclosureGroup("Technical Details", isExpanded: $showFullDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailRow(label: "Payment ID", value: payment.id, isMonospace: true, isCopyable: true)

                            if let preimage = payment.preimage {
                                DetailRow(label: "Preimage", value: preimage, isMonospace: true, isCopyable: true)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(payment.type == .receive ? "Received Payment" : "Sent Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") sats"
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    var isCopyable: Bool = false

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(value)
                    .font(isMonospace ? .caption.monospaced() : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(isMonospace ? 2 : nil)

                if isCopyable {
                    Spacer()
                    Button {
                        UIPasteboard.general.string = value
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                }
            }
        }
    }
}

// MARK: - QR Code Generator

struct QRCodeView: View {
    let content: String
    let size: CGFloat

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .cornerRadius(12)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "qrcode")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering
        let scale = size / outputImage.extent.size.width * UIScreen.main.scale
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Receive View (Lightning Address First per UX Guidelines)

struct ReceiveView: View {
    @ObservedObject var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var invoice: String?
    @State private var amount: String = ""
    @State private var isGenerating = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Receive Method", selection: $selectedTab) {
                    Text("Lightning Address").tag(0)
                    Text("Invoice").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                ScrollView {
                    if selectedTab == 0 {
                        lightningAddressView
                    } else {
                        invoiceView
                    }
                }
            }
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Lightning Address View (Primary per UX guidelines)

    private var lightningAddressView: some View {
        VStack(spacing: 24) {
            if let address = walletManager.lightningAddress {
                // QR Code for LNURL-pay
                QRCodeView(content: "lightning:\(address)", size: 220)
                    .padding(.top, 20)

                // Address display
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(OlasTheme.Colors.zapGold)
                        Text(address)
                            .font(.body.monospaced())
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Text("Share this address to receive payments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = address
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied!" : "Copy")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.deepTeal)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }

                    ShareLink(item: address) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                }
                .padding(.top, 8)

            } else {
                // No lightning address setup
                VStack(spacing: 16) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("No Lightning Address")
                        .font(.title3.bold())

                    Text("Set up a Lightning Address in settings to receive payments easily.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("You can still receive using invoices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Invoice View (Fallback)

    private var invoiceView: some View {
        VStack(spacing: 24) {
            if let invoiceString = invoice {
                invoiceDisplay(invoiceString)
            } else {
                invoiceForm
            }
        }
        .padding()
    }

    private var invoiceForm: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(OlasTheme.Colors.deepTeal)

            Text("Create Invoice")
                .font(.title2.bold())

            Text("Generate a one-time invoice for a specific amount.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Amount (sats)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Enter amount", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await generateInvoice() }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Generate Invoice")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.deepTeal)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(isGenerating)

            Spacer()
        }
    }

    private func invoiceDisplay(_ invoiceString: String) -> some View {
        VStack(spacing: 20) {
            Text("Lightning Invoice")
                .font(.title2.bold())

            QRCodeView(content: invoiceString, size: 220)

            Text(invoiceString)
                .font(.caption.monospaced())
                .lineLimit(3)
                .truncationMode(.middle)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = invoiceString
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.deepTeal)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }

                ShareLink(item: invoiceString) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
            }

            Button("Generate New Invoice") {
                self.invoice = nil
            }
            .foregroundStyle(OlasTheme.Colors.deepTeal)

            Spacer()
        }
    }

    private func generateInvoice() async {
        isGenerating = true
        defer { isGenerating = false }

        let amountSats: Int64? = Int64(amount)

        do {
            let newInvoice = try await walletManager.createInvoice(amountSats: amountSats, description: nil)
            invoice = newInvoice
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Send View (with parsing, fees, and scanner)

struct SendView: View {
    @ObservedObject var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    enum SendState {
        case input
        case parsed(SparkParsedInput)
        case confirm(SparkPreparedPayment)
        case sending
        case success
    }

    @State private var state: SendState = .input
    @State private var inputText: String = ""
    @State private var customAmount: String = ""
    @State private var error: String?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch state {
                case .input:
                    inputView
                case .parsed(let parsed):
                    parsedView(parsed)
                case .confirm(let prepared):
                    confirmView(prepared)
                case .sending:
                    sendingView
                case .success:
                    successView
                }
            }
            .padding()
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedCode in
                    inputText = scannedCode
                    showScanner = false
                    Task { await parseInput() }
                }
            }
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.zapGold)

            Text("Send Payment")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Invoice, Address, or Lightning Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextEditor(text: $inputText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    VStack(spacing: 8) {
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }

                        Button {
                            if let pasted = UIPasteboard.general.string {
                                inputText = pasted
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                }
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await parseInput() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(inputText.isEmpty ? .gray : OlasTheme.Colors.zapGold)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(inputText.isEmpty)

            Spacer()
        }
    }

    // MARK: - Parsed View (amount entry if needed)

    private func parsedView(_ parsed: SparkParsedInput) -> some View {
        VStack(spacing: 20) {
            // Type indicator
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(parsed.typeDescription)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            // Details based on type
            switch parsed {
            case .bolt11Invoice(let details):
                invoiceDetails(details)
            case .lnurlPay(let details):
                lnurlPayDetails(details)
            case .bitcoinAddress(let details):
                bitcoinDetails(details)
            case .sparkAddress(let details):
                sparkAddressDetails(details)
            default:
                Text("Ready to send")
            }

            // Amount input if needed
            if parsed.requiresAmount {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount (sats)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Enter amount", text: $customAmount)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)

                        Button {
                            customAmount = "\(walletManager.balance)"
                        } label: {
                            Text("Max")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    state = .input
                    error = nil
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    Task { await preparePayment(parsed) }
                } label: {
                    Text("Review Payment")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canProceed(parsed) ? OlasTheme.Colors.zapGold : .gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!canProceed(parsed))
            }

            Spacer()
        }
    }

    private func invoiceDetails(_ details: SparkBolt11Details) -> some View {
        VStack(spacing: 12) {
            if let amount = details.amountSats {
                Text("\(formatSats(amount))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }

            if let description = details.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func lnurlPayDetails(_ details: SparkLnurlPayDetails) -> some View {
        VStack(spacing: 12) {
            if let address = details.lightningAddress {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(OlasTheme.Colors.zapGold)
                    Text(address)
                        .font(.body.monospaced())
                }
            }

            Text("Min: \(formatSats(details.minSendableSats)) • Max: \(formatSats(details.maxSendableSats))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bitcoinDetails(_ details: SparkBitcoinAddressDetails) -> some View {
        VStack(spacing: 8) {
            Text(details.address)
                .font(.caption.monospaced())
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let amount = details.amountSats {
                Text("\(formatSats(amount))")
                    .font(.title2.bold())
            }
        }
    }

    private func sparkAddressDetails(_ details: SparkAddressDetails) -> some View {
        Text(details.address)
            .font(.caption.monospaced())
            .lineLimit(2)
    }

    // MARK: - Confirm View (shows fees)

    private func confirmView(_ prepared: SparkPreparedPayment) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.zapGold)

            Text("Confirm Payment")
                .font(.title2.bold())

            VStack(spacing: 16) {
                // Amount breakdown
                VStack(spacing: 8) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text(formatSats(prepared.amountSats))
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Network Fee")
                        Spacer()
                        Text(formatSats(prepared.feeSats))
                            .fontWeight(.medium)
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(formatSats(prepared.totalSats))
                            .font(.title3.bold())
                            .foregroundStyle(OlasTheme.Colors.zapGold)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Balance after
                HStack {
                    Text("Balance after")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatSats(walletManager.balance - prepared.totalSats))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    state = .input
                    error = nil
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    Task { await sendPayment(prepared) }
                } label: {
                    Text("Send Payment")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.zapGold)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
            }

            Spacer()
        }
    }

    // MARK: - Sending View

    private var sendingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Sending Payment...")
                .font(.title2.bold())

            Text("Please wait while we process your payment.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Payment Sent!")
                .font(.title.bold())

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OlasTheme.Colors.deepTeal)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func parseInput() async {
        error = nil
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let parsed = try await walletManager.parseInput(trimmed)
            state = .parsed(parsed)
        } catch {
            self.error = "Could not parse input: \(error.localizedDescription)"
        }
    }

    private func preparePayment(_ parsed: SparkParsedInput) async {
        error = nil

        let amount: Int64?
        if parsed.requiresAmount {
            guard let parsedAmount = Int64(customAmount), parsedAmount > 0 else {
                error = "Please enter a valid amount"
                return
            }
            amount = parsedAmount
        } else {
            amount = parsed.embeddedAmountSats
        }

        do {
            let prepared = try await walletManager.preparePayment(input: inputText.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount)
            state = .confirm(prepared)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendPayment(_ prepared: SparkPreparedPayment) async {
        state = .sending
        error = nil

        do {
            try await walletManager.sendPreparedPayment(prepared)
            state = .success
        } catch {
            self.error = error.localizedDescription
            state = .confirm(prepared)
        }
    }

    private func canProceed(_ parsed: SparkParsedInput) -> Bool {
        if parsed.requiresAmount {
            return Int64(customAmount) ?? 0 > 0
        }
        return true
    }

    private func formatSats(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") sats"
    }
}

// MARK: - QR Scanner View

struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                // Placeholder for actual camera scanner
                // In a real implementation, use AVFoundation or a library like CodeScanner
                VStack(spacing: 20) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 100))
                        .foregroundStyle(.secondary)

                    Text("Point camera at QR code")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Camera access required")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9))
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
