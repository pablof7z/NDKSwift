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
            HStack(spacing: 4) {
                Image(systemName: zapState.iconName)
                    .font(.system(size: size.iconSize))
                    .foregroundColor(zapState.color)
                    .scaleEffect(zapState == .zapping ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: zapState)
                
            }
            .padding(size.padding)
        }
        .disabled(zapState == .zapping)
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
                // TODO: Implement actual zapping once NDK supports it
                // This would create a zap event (kind 9735) and send payment
                // For now, just show success immediately
                
                await MainActor.run {
                    zapState = .zapped
                    HapticType.success.trigger()
                }
            } catch {
                await MainActor.run {
                    zapState = .failed
                    HapticType.error.trigger()
                    print("Zap failed: \(error)")
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
                // Lightning bolt animation
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .scaleEffect(1.1)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: true
                    )
                    .padding(.top)
                
                Text("Choose Amount")
                    .font(DesignSystem.Typography.headline)
                
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
