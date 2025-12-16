import NDKSwiftCashu
import NDKSwiftCore
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - NDKZapButton

/// A button component for sending Lightning payments (zaps) to Nostr events.
///
/// Features:
/// - Lightning payment integration via NDKZapManager
/// - Predefined amount buttons
/// - Custom amount input
/// - Zap count display
/// - Payment confirmation
/// - Loading and success states
/// - Integration with NIP-57 zap protocol
///
/// ## Usage
///
/// ```swift
/// // Basic zap button with default amounts
/// NDKZapButton(ndk: ndk, event: event, amounts: [21, 100, 1000])
///     .onZapSent { amount in
///         print("Sent \(amount) sats!")
///     }
///
/// // Custom styling
/// NDKZapButton(ndk: ndk, event: event, style: .compact, showCount: true, customAmountEnabled: true)
/// ```
public struct NDKZapButton: View {
    // MARK: - Properties

    private let ndk: NDK
    private let event: NDKEvent
    private let style: ButtonStyle
    private let amounts: [Int]
    private let showCount: Bool
    private let customAmountEnabled: Bool
    private let defaultAmount: Int
    private let preferredProvider: String?
    private var onZapSent: ((Int) -> Void)?
    private var onZapFailed: ((Error) -> Void)?

    @StateObject private var zapState: ZapState
    @State private var showAmountSelector = false
    @State private var showCustomAmount = false
    @State private var customAmount = ""

    // MARK: - Supporting Types

    public enum ButtonStyle {
        case standard // Full button with background
        case compact // Small icon button
        case minimal // Text-based button
    }

    // MARK: - Initialization

    /// Initialize a zap button
    /// - Parameters:
    ///   - ndk: The NDK instance to use for operations
    ///   - event: The event to zap
    ///   - style: Button presentation style
    ///   - amounts: Predefined zap amounts in sats
    ///   - defaultAmount: Default amount when tapped directly
    ///   - showCount: Whether to show total zap count
    ///   - customAmountEnabled: Whether to allow custom amounts
    ///   - preferredProvider: Optional ID of the payment provider to use (e.g., "nwc_wallet", "nip60")
    public init(
        ndk: NDK,
        event: NDKEvent,
        style: ButtonStyle = .standard,
        amounts: [Int] = [21, 100, 1000],
        defaultAmount: Int = 21,
        showCount: Bool = true,
        customAmountEnabled: Bool = true,
        preferredProvider: String? = nil
    ) {
        self.ndk = ndk
        self.event = event
        self.style = style
        self.amounts = amounts
        self.defaultAmount = defaultAmount
        self.showCount = showCount
        self.customAmountEnabled = customAmountEnabled
        self.preferredProvider = preferredProvider

        // Initialize zap state
        _zapState = StateObject(wrappedValue: ZapState(eventId: event.id))
    }

    // MARK: - Body

    public var body: some View {
        Button(action: handleTap) {
            HStack(spacing: buttonSpacing) {
                // Lightning bolt icon
                Image(systemName: zapState.isLoading ? "bolt.fill" : "bolt")
                    .font(iconFont)
                    .foregroundStyle(zapState.hasZapped ? zapColor : inactiveColor)
                    .scaleEffect(zapState.showSuccess ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: zapState.showSuccess)

                // Count (if enabled and > 0)
                if showCount && zapState.totalAmount > 0 {
                    Text(formatAmount(zapState.totalAmount))
                        .font(countFont)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: zapState.totalAmount)
                }
            }
            .padding(buttonPadding)
            .background(backgroundColor)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(zapState.isLoading || ndk.signer == nil)
        .opacity(zapState.isLoading ? OpacityConstants.secondary : 1.0)
        .contextMenu {
            if !amounts.isEmpty {
                ForEach(amounts, id: \.self) { amount in
                    Button("\(amount) sats") {
                        zapAmount(amount)
                    }
                }

                if customAmountEnabled {
                    Divider()
                    Button("Custom Amount...") {
                        showCustomAmount = true
                    }
                }
            }
        }
        .sheet(isPresented: $showAmountSelector) {
            AmountSelectorSheet(
                amounts: amounts,
                customAmountEnabled: customAmountEnabled,
                onAmountSelected: { amount in
                    zapAmount(amount)
                    showAmountSelector = false
                }
            )
        }
        .sheet(isPresented: $showCustomAmount) {
            CustomAmountSheet(
                onAmountEntered: { amount in
                    zapAmount(amount)
                    showCustomAmount = false
                }
            )
        }
        .onAppear {
            setupZapObservation()
        }
        .onChange(of: zapState.showSuccess) { _, showSuccess in
            if showSuccess {
                // Hide success state after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    zapState.showSuccess = false
                }
            }
        }
    }

    // MARK: - Private Methods

    private func handleTap() {
        if amounts.count == 1 {
            // Single amount - zap directly
            zapAmount(amounts[0])
        } else if amounts.isEmpty {
            // No predefined amounts - use default
            zapAmount(defaultAmount)
        } else {
            // Multiple amounts - show selector
            showAmountSelector = true
        }

        // Haptic feedback
        #if canImport(UIKit)
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        #endif
    }

    private func zapAmount(_ amount: Int) {
        Task {
            await zapState.sendZap(
                ndk: ndk,
                event: event,
                amount: amount,
                preferredProvider: preferredProvider
            )

            if zapState.lastZapSucceeded {
                onZapSent?(amount)
                zapState.showSuccess = true

                // Success haptic
                #if canImport(UIKit)
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                #endif
            } else if let error = zapState.lastError {
                onZapFailed?(error)

                // Error haptic
                #if canImport(UIKit)
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.error)
                #endif
            }
        }
    }

    private func setupZapObservation() {
        Task {
            await zapState.startObserving(ndk: ndk)
        }
    }

    private func formatAmount(_ amount: Int) -> String {
        if amount >= 1_000_000 {
            return String(format: "%.1fM", Double(amount) / 1_000_000)
        } else if amount >= 1000 {
            return String(format: "%.1fK", Double(amount) / 1000)
        } else {
            return "\(amount)"
        }
    }

    // MARK: - Style Properties

    private var buttonSpacing: CGFloat {
        switch style {
        case .standard: return 4
        case .compact: return 2
        case .minimal: return 4
        }
    }

    private var iconFont: Font {
        switch style {
        case .standard: return .title3
        case .compact: return .body
        case .minimal: return .body
        }
    }

    private var countFont: Font {
        switch style {
        case .standard: return .caption
        case .compact: return .caption2
        case .minimal: return .caption
        }
    }

    private var buttonPadding: EdgeInsets {
        switch style {
        case .standard: return EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        case .compact: return EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        case .minimal: return EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard:
            return zapState.hasZapped ? zapColor.opacity(OpacityConstants.subtle) : Color.ndkTertiaryBackground
        case .compact:
            return zapState.hasZapped ? zapColor.opacity(OpacityConstants.subtle) : Color.clear
        case .minimal:
            return Color.clear
        }
    }

    private var borderOverlay: some View {
        Group {
            if style == .standard {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(zapState.hasZapped ? zapColor.opacity(OpacityConstants.border) : Color.ndkSeparator.opacity(OpacityConstants.border), lineWidth: 1)
            }
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .standard: return 16
        case .compact: return 12
        case .minimal: return 8
        }
    }

    private var zapColor: Color {
        .orange // Lightning color
    }

    private var inactiveColor: Color {
        .secondary
    }

    // MARK: - Modifiers

    /// Handle successful zap events
    public func onZapSent(_ action: @escaping (Int) -> Void) -> NDKZapButton {
        var copy = self
        copy.onZapSent = action
        return copy
    }

    /// Handle zap failure events
    public func onZapFailed(_ action: @escaping (Error) -> Void) -> NDKZapButton {
        var copy = self
        copy.onZapFailed = action
        return copy
    }
}

// MARK: - ZapState

/// Observable state for managing zap data and interactions
@MainActor
private class ZapState: ObservableObject {
    @Published var hasZapped: Bool = false
    @Published var totalAmount: Int = 0
    @Published var isLoading: Bool = false
    @Published var showSuccess: Bool = false
    @Published var lastError: Error?
    @Published var lastZapSucceeded: Bool = false

    private let eventId: String
    private var observationTask: Task<Void, Never>?

    init(eventId: String) {
        self.eventId = eventId
    }

    deinit {
        observationTask?.cancel()
    }

    func startObserving(ndk: NDK) async {
        // Cancel existing observation
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            await self?.observeZaps(ndk: ndk)
        }
    }

    private func observeZaps(ndk: NDK) async {
        // Create filter for zap receipt events (kind:9735) referencing our event
        let filter = NDKFilter(
            kinds: [9735], // Zap receipt events
            tags: ["e": Set([eventId])] // Events that reference our event
        )

        let dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0, // Real-time
            cachePolicy: .cacheWithNetwork
        )

        // Process zap events
        for await batch in dataSource.events {
            for _ in batch {
                await updateZapState(from: dataSource.data, ndk: ndk)
            }
        }
    }

    private func updateZapState(from events: [NDKEvent], ndk: NDK) async {
        var totalAmount = 0
        var userZapped = false

        // Get current user's pubkey
        let userPubkey = try? await ndk.signer?.pubkey

        // Process all zap receipt events
        for event in events {
            // Extract amount from bolt11 invoice in the event
            if let amount = extractAmountFromZapReceipt(event) {
                totalAmount += amount

                // Check if this zap came from the current user
                // This would require parsing the zap request to get the original sender
                if let userPubkey = userPubkey,
                   let zapSender = extractZapSender(event),
                   zapSender == userPubkey
                {
                    userZapped = true
                }
            }
        }

        // Update state
        await MainActor.run {
            self.totalAmount = totalAmount
            self.hasZapped = userZapped
        }
    }

    private func extractAmountFromZapReceipt(_ event: NDKEvent) -> Int? {
        // Look for bolt11 tag and extract amount
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "bolt11" {
                let invoice = tag[1]
                // Parse Lightning invoice for amount using comprehensive Bolt11 parser
                return parseInvoiceAmount(invoice)
            }
        }
        return nil
    }

    private func extractZapSender(_ event: NDKEvent) -> String? {
        // Look for description tag containing the zap request
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "description" {
                let zapRequestJson = tag[1]
                // Parse the embedded zap request to get the sender
                // This would need proper JSON parsing
                return parseZapRequestSender(zapRequestJson)
            }
        }
        return nil
    }

    private func parseInvoiceAmount(_ invoice: String) -> Int? {
        // Use comprehensive Bolt11 parser
        guard let parsedInvoice = Bolt11Parser.decode(string: invoice),
              let amount = parsedInvoice.amount
        else {
            return nil
        }

        // Convert millisatoshis to satoshis for display
        return Int(PaymentConstants.millisatsToSats(amount.int64))
    }

    private func parseZapRequestSender(_: String) -> String? {
        // Parse JSON to extract the pubkey from the zap request
        return nil
    }

    func sendZap(ndk: NDK, event: NDKEvent, amount: Int, preferredProvider: String? = nil) async {
        let zapManager = ndk.zapManager

        isLoading = true
        lastError = nil
        lastZapSucceeded = false

        defer { isLoading = false }

        do {
            // Send zap using NDKZapManager
            guard let recipient = ndk.getUser(event.pubkey) else {
                throw NDKError.invalidDataFormat("pubkey", details: "Invalid event author pubkey")
            }
            _ = try await zapManager.zap(
                event: event,
                to: recipient,
                amountSats: Int64(amount),
                comment: nil, // Could be made configurable
                preferredType: nil,
                preferredProvider: preferredProvider
            )

            lastZapSucceeded = true

        } catch {
            lastError = error
            lastZapSucceeded = false
        }
    }
}

// MARK: - Supporting Views

/// Sheet for selecting predefined amounts
private struct AmountSelectorSheet: View {
    let amounts: [Int]
    let customAmountEnabled: Bool
    let onAmountSelected: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("⚡ Send Zap")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose an amount to send")
                    .font(.body)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 16) {
                    ForEach(amounts, id: \.self) { amount in
                        Button(action: { onAmountSelected(amount) }) {
                            VStack(spacing: 8) {
                                Text("\(amount)")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text("sats")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.ndkSecondaryBackground)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                if customAmountEnabled {
                    Button("Custom Amount") {
                        // This would trigger custom amount input
                    }
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                }

                Spacer()
            }
            .padding()
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// Sheet for entering custom amounts
private struct CustomAmountSheet: View {
    @State private var amountText = ""
    @Environment(\.dismiss) private var dismiss

    let onAmountEntered: (Int) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("⚡ Custom Zap")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount (sats)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Enter amount", text: $amountText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                Button("Send Zap") {
                    if let amount = Int(amountText), amount > 0 {
                        onAmountEntered(amount)
                    }
                }
                .disabled(Int(amountText) == nil || Int(amountText) ?? 0 <= 0)

                Spacer()
            }
            .padding()
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - ZapError

private enum ZapError: LocalizedError {
    case zapManagerNotAvailable
    case invalidAmount
    case networkError

    var errorDescription: String? {
        switch self {
        case .zapManagerNotAvailable:
            return "Zap manager is not available"
        case .invalidAmount:
            return "Invalid zap amount"
        case .networkError:
            return "Network error occurred"
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKZapButton_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK = NDK(relayURLs: [])

            VStack(spacing: 20) {
                // Different styles
                HStack(spacing: 16) {
                    NDKZapButton(ndk: mockNDK, event: mockEvent, style: .standard)
                    NDKZapButton(ndk: mockNDK, event: mockEvent, style: .compact)
                    NDKZapButton(ndk: mockNDK, event: mockEvent, style: .minimal)
                }

                // Different configurations
                HStack(spacing: 16) {
                    NDKZapButton(ndk: mockNDK, event: mockEvent, amounts: [21])
                    NDKZapButton(ndk: mockNDK, event: mockEvent, amounts: UIConstants.ZapAmounts.standard)
                    NDKZapButton(ndk: mockNDK, event: mockEvent, showCount: false)
                }
            }
            .padding()
        }

        // Mock event for preview
        private static let mockEvent = NDKEvent(
            id: "mock_id",
            pubkey: "mock_pubkey",
            createdAt: Date.currentNostrTimestamp,
            kind: EventKind.textNote,
            tags: [],
            content: "Mock event content",
            sig: "mock_sig"
        )
    }
#endif
