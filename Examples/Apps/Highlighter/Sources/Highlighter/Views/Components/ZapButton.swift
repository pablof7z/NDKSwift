import SwiftUI
import NDKSwift

struct ZapButton: View {
    let event: NDKEvent
    let size: ButtonSize
    
    @EnvironmentObject var appState: AppState
    @State private var zapState: ZapState = .idle
    @State private var showZapSheet = false
    @State private var zapAmount = 21
    
    enum ButtonSize {
        case small, medium, large
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 20
            case .large: return 24
            }
        }
        
        var padding: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 12
            case .large: return 16
            }
        }
    }
    
    enum ZapState {
        case idle
        case zapping
        case zapped
        case failed
        
        var iconName: String {
            switch self {
            case .idle: return "bolt"
            case .zapping: return "bolt"
            case .zapped: return "bolt.fill"
            case .failed: return "bolt.slash"
            }
        }
        
        var color: Color {
            switch self {
            case .idle: return DesignSystem.Colors.textSecondary
            case .zapping: return DesignSystem.Colors.primaryDark
            case .zapped: return DesignSystem.Colors.primary
            case .failed: return .red
            }
        }
    }
    
    var body: some View {
        Button(action: handleZap) {
            HStack(spacing: 6) {
                Image(systemName: zapState.iconName)
                    .font(.system(size: size.iconSize, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(zapState == .zapping ? 1.3 : 1.0)
                    .rotationEffect(zapState == .zapping ? .degrees(15) : .degrees(0))
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.6),
                        value: zapState
                    )
                
                if zapState == .zapped {
                    Text("\(zapAmount)")
                        .font(.system(size: size.iconSize * 0.8, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, size.padding)
            .padding(.vertical, size.padding * 0.75)
        }
        .enhancedZapButton()
        .contextualFeedback(isActive: zapState == .zapping)
        .disabled(zapState == .zapping)
        .opacity(zapState == .failed ? 0.6 : 1.0)
        .sheet(isPresented: $showZapSheet) {
            ZapAmountSheet(
                event: event,
                zapAmount: $zapAmount,
                onZap: performZap
            )
            .environmentObject(appState)
        }
    }
    
    private func handleZap() {
        HapticType.light.trigger()
        
        // If already zapped, show amount picker to zap again
        if zapState == .zapped {
            showZapSheet = true
        } else {
            // Quick zap with default amount
            performZap(amount: zapAmount)
        }
    }
    
    private func performZap(amount: Int) {
        guard let ndk = appState.ndk else { return }
        
        zapState = .zapping
        HapticType.medium.trigger()
        
        Task {
            do {
                // Add realistic delay for better UX feedback
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                
                // TODO: Implement actual zapping once NDK supports it
                // This would create a zap event (kind 9735) and send payment
                // For now, just show success immediately
                
                await MainActor.run {
                    zapAmount = amount
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        zapState = .zapped
                    }
                    
                    // Multiple haptic feedback for success
                    HapticType.success.trigger()
                    
                    // Add a subtle second feedback after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        HapticType.light.trigger()
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        zapState = .failed
                    }
                    HapticType.error.trigger()
                    print("Zap failed: \(error)")
                    
                    // Auto-reset failed state after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            zapState = .idle
                        }
                    }
                }
            }
        }
    }
}

struct ZapAmountSheet: View {
    let event: NDKEvent
    @Binding var zapAmount: Int
    let onZap: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    
    let presetAmounts = [21, 42, 69, 100, 420, 1000, 5000, 10000]
    @State private var customAmount = ""
    @State private var useCustomAmount = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Enhanced lightning bolt animation
                ZStack {
                    // Background glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DesignSystem.Colors.secondary.opacity(0.3),
                                    DesignSystem.Colors.secondary.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                        .pulseGently()
                    
                    // Main lightning bolt
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.secondary,
                                    DesignSystem.Colors.secondaryDark
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: DesignSystem.Colors.secondary.opacity(0.4),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                }
                .padding(.top)
                
                VStack(spacing: 8) {
                    Text("Choose Amount")
                        .font(.system(size: 24, weight: .semibold))
                    
                    Text("Send sats to show appreciation")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Preset amounts grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                    ForEach(presetAmounts, id: \.self) { amount in
                        Button(action: {
                            zapAmount = amount
                            useCustomAmount = false
                            customAmount = ""
                        }) {
                            Text("\(amount)")
                                .font(DesignSystem.Typography.body)
                                .fontWeight(.medium)
                                .frame(width: 80, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(zapAmount == amount && !useCustomAmount ? DesignSystem.Colors.primaryDark : DesignSystem.Colors.surface)
                                )
                                .foregroundColor(zapAmount == amount && !useCustomAmount ? .white : DesignSystem.Colors.text)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Custom amount
                HStack {
                    TextField("Custom amount", text: $customAmount)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: customAmount) { _ in
                            useCustomAmount = !customAmount.isEmpty
                            if let amount = Int(customAmount) {
                                zapAmount = amount
                            }
                        }
                    
                    Text("sats")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Zap button
                Button(action: {
                    onZap(zapAmount)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Zap \(zapAmount) sats")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("⚡ Zap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ZapButton(
                event: NDKEvent(id: "", pubkey: "", createdAt: 0, kind: 1, tags: [], content: "", sig: ""),
                size: .small
            )
            
            ZapButton(
                event: NDKEvent(id: "", pubkey: "", createdAt: 0, kind: 1, tags: [], content: "", sig: ""),
                size: .medium
            )
            
            ZapButton(
                event: NDKEvent(id: "", pubkey: "", createdAt: 0, kind: 1, tags: [], content: "", sig: ""),
                size: .large
            )
        }
    }
    .padding()
    .environmentObject(AppState())
}
