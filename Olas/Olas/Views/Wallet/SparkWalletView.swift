import SwiftUI
import NDKSwift
import NDKSwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Main Wallet View

struct SparkWalletView: View {
    var walletManager: SparkWalletManager

    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if walletManager.connectionStatus == .connected {
                    connectedView
                } else {
                    setupView
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if walletManager.connectionStatus == .connected {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCreateWallet) {
                CreateSparkWalletView(walletManager: walletManager)
            }
            .sheet(isPresented: $showImportWallet) {
                ImportSparkWalletView(walletManager: walletManager)
            }
            .fullScreenCover(isPresented: $showReceive) {
                ReceiveView(walletManager: walletManager)
            }
            .fullScreenCover(isPresented: $showSend) {
                SparkSendView(walletManager: walletManager)
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Balance - tappable to switch sats/fiat
                balanceDisplay
                    .padding(.top, 32)
                    .padding(.bottom, 40)

                // Action buttons
                actionButtons
                    .padding(.horizontal, 20)

                // Activity (only if not empty)
                if !walletManager.payments.isEmpty {
                    activityList
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await walletManager.sync()
        }
    }

    private var balanceDisplay: some View {
        Button {
            walletManager.togglePrimaryDisplay()
        } label: {
            VStack(spacing: 6) {
                // Primary amount
                if walletManager.showFiatAsPrimary, let fiat = walletManager.satsToFiat(walletManager.balance) {
                    Text(walletManager.formatFiat(fiat))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(walletManager.formatSats(walletManager.balance))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text("sats")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // Secondary amount
                if walletManager.showFiatAsPrimary {
                    Text("\(walletManager.formatSats(walletManager.balance)) sats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let fiat = walletManager.satsToFiat(walletManager.balance) {
                    Text(walletManager.formatFiat(fiat))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Loading or lightning address
                if walletManager.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            }
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.3), value: walletManager.balance)
            .animation(.spring(duration: 0.2), value: walletManager.showFiatAsPrimary)
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Receive
            Button {
                showReceive = true
            } label: {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(OlasTheme.Colors.success)
                            .frame(width: 56, height: 56)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Receive")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            // Send
            Button {
                showSend = true
            } label: {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(OlasTheme.Colors.brandPrimary)
                            .frame(width: 56, height: 56)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Send")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(walletManager.payments.enumerated()), id: \.element.id) { index, payment in
                    SparkTransactionRow(payment: payment, walletManager: walletManager)

                    if index < walletManager.payments.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [OlasTheme.Colors.zapGold, OlasTheme.Colors.brandPrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Lightning Wallet")
                        .font(.title.bold())
                    Text("Self-custodial Bitcoin")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if walletManager.connectionStatus == .connecting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
            }

            if let error = walletManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }

            VStack(spacing: 12) {
                Button {
                    showCreateWallet = true
                } label: {
                    Text("Create Wallet")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(OlasTheme.Colors.brandPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    showImportWallet = true
                } label: {
                    Text("I Have a Wallet")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Transaction Row

struct SparkTransactionRow: View {
    let payment: SparkPayment
    let walletManager: SparkWalletManager
    @State private var isExpanded = false

    private var isReceive: Bool { payment.type == .receive }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isReceive ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: isReceive ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isReceive ? .green : .orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(payment.description ?? (isReceive ? "Received" : "Sent"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(formatRelativeTime(payment.timestamp))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(isReceive ? "+" : "-")\(walletManager.formatSats(payment.amountSats))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isReceive ? .green : .primary)

                        if let fiat = walletManager.satsToFiat(payment.amountSats) {
                            Text(walletManager.formatFiat(fiat))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if isExpanded {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, 74)

                        VStack(spacing: 10) {
                            if payment.feeSats > 0 {
                                detailRow("Fee", "\(payment.feeSats) sats")
                            }
                            detailRow("Status", payment.status.displayName)
                            detailRow("Time", payment.timestamp.formatted(.dateTime.month().day().hour().minute()))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .padding(.leading, 58)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension SparkPaymentStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }
}

// MARK: - QR Code View

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
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "qrcode")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = size / outputImage.extent.size.width * UIScreen.main.scale
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Receive View

struct ReceiveView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var invoice: String?
    @State private var isGenerating = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if let invoiceString = invoice {
                invoiceResultView(invoiceString)
            } else {
                amountEntryView
            }
        }
    }

    private var amountEntryView: some View {
        VStack(spacing: 0) {
            header(title: "Receive", leadingAction: { dismiss() }, leadingIcon: "xmark")

            Spacer()

            VStack(spacing: 12) {
                Text(amount.isEmpty ? "0" : formatWithCommas(amount))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(amount.isEmpty ? .quaternary : .primary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: amount)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("sats")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)

                // Show fiat equivalent
                if let sats = Int64(amount), let fiat = walletManager.satsToFiat(sats) {
                    Text(walletManager.formatFiat(fiat))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 32)

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 16)
            }

            Spacer()

            numpadView { key in handleKey(key) }
                .padding(.horizontal, 24)

            Button {
                Task { await generateInvoice() }
            } label: {
                HStack(spacing: 10) {
                    if isGenerating { ProgressView().tint(.white) }
                    Text("Create Invoice")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(amount.isEmpty ? Color(.systemGray3) : OlasTheme.Colors.success)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(amount.isEmpty || isGenerating)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
    }

    private func handleKey(_ key: String) {
        if key == "delete" {
            if !amount.isEmpty { amount.removeLast() }
        } else if amount.count < 10 {
            if amount == "0" { amount = key }
            else { amount += key }
        }
    }

    private func invoiceResultView(_ invoiceString: String) -> some View {
        VStack(spacing: 0) {
            header(
                title: "Invoice Ready",
                leadingAction: { invoice = nil; amount = "" },
                leadingIcon: "chevron.left",
                trailingAction: { dismiss() },
                trailingLabel: "Done"
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text(formatWithCommas(amount))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("sats")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 16) {
                        QRCodeView(content: invoiceString, size: 200)

                        Button {
                            UIPasteboard.general.string = invoiceString
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(invoiceString.prefix(24)) + "...")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(copied ? .green : .secondary)
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 24)

                    ShareLink(item: invoiceString) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.medium))
                            Text("Share Invoice")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(OlasTheme.Colors.brandPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
            }
        }
    }

    private func formatWithCommas(_ str: String) -> String {
        guard let value = Int64(str) else { return str }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? str
    }

    private func generateInvoice() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        guard let amountSats = Int64(amount) else { return }

        do {
            invoice = try await walletManager.createInvoice(amountSats: amountSats, description: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Send View (Scanner First)

struct SparkSendView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss

    enum SendStep: Equatable {
        case scan
        case manualEntry
        case amount(SparkParsedInput)
        case confirm(SparkPreparedPayment)
        case processing
        case success

        static func == (lhs: SendStep, rhs: SendStep) -> Bool {
            switch (lhs, rhs) {
            case (.scan, .scan), (.manualEntry, .manualEntry),
                 (.processing, .processing), (.success, .success):
                return true
            case (.amount, .amount), (.confirm, .confirm):
                return true
            default:
                return false
            }
        }
    }

    @State private var step: SendStep = .scan
    @State private var destination = ""
    @State private var amount = ""
    @State private var error: String?
    @State private var isParsing = false

    var body: some View {
        ZStack {
            switch step {
            case .scan:
                scannerView
            case .manualEntry:
                manualEntryView
            case .amount(let parsed):
                amountView(parsed)
            case .confirm(let prepared):
                confirmView(prepared)
            case .processing:
                processingView
            case .success:
                successView
            }
        }
    }

    // MARK: - Scanner View (Primary)

    private var scannerView: some View {
        ZStack {
            NDKUIQRScanner(
                onScan: { code in
                    destination = code
                    Task { await parseDestination() }
                },
                onDismiss: { dismiss() }
            )
            .ignoresSafeArea()

            // Bottom button for manual entry
            VStack {
                Spacer()

                Button {
                    step = .manualEntry
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.body.weight(.medium))
                        Text("Enter Manually")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .clipShape(Capsule())
                }
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Manual Entry View

    private var manualEntryView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header(title: "Send", leadingAction: { step = .scan }, leadingIcon: "chevron.left")

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("To")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("Invoice, address, or Lightning address", text: $destination, axis: .vertical)
                            .font(.body)
                            .lineLimit(3...6)
                            .padding(16)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        // Paste button
                        Button {
                            if let pasted = UIPasteboard.general.string {
                                destination = pasted
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Paste from Clipboard")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer()

                Button {
                    Task { await parseDestination() }
                } label: {
                    HStack(spacing: 10) {
                        if isParsing { ProgressView().tint(.white) }
                        Text("Continue")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(destination.isEmpty ? Color(.systemGray3) : OlasTheme.Colors.brandPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(destination.isEmpty || isParsing)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Amount View

    private func amountView(_ parsed: SparkParsedInput) -> some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header(title: "Amount", leadingAction: { step = .scan; error = nil }, leadingIcon: "chevron.left")

                Spacer()

                VStack(spacing: 12) {
                    if let embedded = parsed.embeddedAmountSats {
                        Text(walletManager.formatSats(embedded))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                    } else {
                        Text(amount.isEmpty ? "0" : formatWithCommas(Int64(amount) ?? 0))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(amount.isEmpty ? .quaternary : .primary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.2), value: amount)
                    }

                    Text("sats")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("Available:")
                            .foregroundStyle(.tertiary)
                        Text("\(walletManager.formatSats(walletManager.balance)) sats")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 16)
                }

                Spacer()

                if parsed.embeddedAmountSats == nil {
                    numpadView { key in handleAmountKey(key) }
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await preparePayment(parsed) }
                } label: {
                    Text("Review")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(canContinue(parsed) ? OlasTheme.Colors.brandPrimary : Color(.systemGray3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canContinue(parsed))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func handleAmountKey(_ key: String) {
        if key == "delete" {
            if !amount.isEmpty { amount.removeLast() }
        } else if amount.count < 10 {
            if amount == "0" { amount = key }
            else { amount += key }
        }
    }

    // MARK: - Confirm View

    private func confirmView(_ prepared: SparkPreparedPayment) -> some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header(title: "Confirm", leadingAction: { step = .scan; error = nil }, leadingIcon: "chevron.left")

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        VStack(spacing: 4) {
                            Text(walletManager.formatSats(prepared.amountSats))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                            Text("sats")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            if let fiat = walletManager.satsToFiat(prepared.amountSats) {
                                Text(walletManager.formatFiat(fiat))
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.top, 32)

                        VStack(spacing: 0) {
                            detailRow(label: "Amount", value: "\(walletManager.formatSats(prepared.amountSats)) sats")
                            Divider().padding(.leading, 16)
                            detailRow(label: "Network fee", value: "\(walletManager.formatSats(prepared.feeSats)) sats")
                            Divider().padding(.leading, 16)
                            detailRow(label: "Total", value: "\(walletManager.formatSats(prepared.totalSats)) sats", highlight: true)
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)

                        HStack {
                            Text("Balance after")
                            Spacer()
                            Text("\(walletManager.formatSats(walletManager.balance - prepared.totalSats)) sats")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                        if let error = error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button {
                    Task { await sendPayment(prepared) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.body.weight(.medium))
                        Text("Send \(walletManager.formatSats(prepared.totalSats)) sats")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(OlasTheme.Colors.brandPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func detailRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(highlight ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? .primary : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Processing & Success Views

    private var processingView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                ProgressView().scaleEffect(1.5)
                VStack(spacing: 8) {
                    Text("Sending...")
                        .font(.title2.weight(.semibold))
                    Text("This should only take a moment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var successView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 8) {
                    Text("Sent!")
                        .font(.title.bold())
                    Text("Your payment was successful")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(OlasTheme.Colors.brandPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Actions

    private func parseDestination() async {
        isParsing = true
        error = nil
        defer { isParsing = false }

        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let parsed = try await walletManager.parseInput(trimmed)
            step = .amount(parsed)
        } catch {
            self.error = "Invalid destination"
            if step == .scan {
                step = .manualEntry
            }
        }
    }

    private func preparePayment(_ parsed: SparkParsedInput) async {
        error = nil

        let amountSats: Int64?
        if let embedded = parsed.embeddedAmountSats {
            amountSats = embedded
        } else if let amt = Int64(amount), amt > 0 {
            amountSats = amt
        } else {
            error = "Enter an amount"
            return
        }

        do {
            let prepared = try await walletManager.preparePayment(
                input: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amountSats
            )
            step = .confirm(prepared)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendPayment(_ prepared: SparkPreparedPayment) async {
        step = .processing
        error = nil

        do {
            try await walletManager.sendPreparedPayment(prepared)
            step = .success
        } catch {
            self.error = error.localizedDescription
            step = .confirm(prepared)
        }
    }

    private func canContinue(_ parsed: SparkParsedInput) -> Bool {
        if parsed.embeddedAmountSats != nil { return true }
        return (Int64(amount) ?? 0) > 0
    }

    private func formatWithCommas(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Shared Components

private func header(
    title: String,
    leadingAction: @escaping () -> Void,
    leadingIcon: String,
    trailingAction: (() -> Void)? = nil,
    trailingLabel: String? = nil
) -> some View {
    HStack {
        Button(action: leadingAction) {
            Image(systemName: leadingIcon)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }

        Spacer()

        Text(title)
            .font(.headline)

        Spacer()

        if let action = trailingAction, let label = trailingLabel {
            Button(action: action) {
                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(OlasTheme.Colors.brandPrimary)
            }
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }
    .padding(.horizontal, 8)
}

private func numpadView(onKey: @escaping (String) -> Void) -> some View {
    let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "delete"]

    return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 8) {
        ForEach(keys, id: \.self) { key in
            if key.isEmpty {
                Color.clear.frame(height: 56)
            } else {
                Button {
                    onKey(key)
                } label: {
                    Group {
                        if key == "delete" {
                            Image(systemName: "delete.left")
                                .font(.title3)
                        } else {
                            Text(key)
                                .font(.title.weight(.medium))
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
