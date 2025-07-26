import SwiftUI

// MARK: - Glassmorphic Card
struct GlassmorphicCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = OlasDesign.CornerRadius.lg
    var borderGradient: [Color] = [Color.white.opacity(0.6), Color.white.opacity(0.2)]
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                ZStack {
                    // Base glass effect
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    // Gradient overlay
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: borderGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Animated Balance Display
struct AnimatedBalanceDisplay: View {
    let balance: Int64
    let btcPrice: Double?
    @State private var displayedBalance: Double = 0
    @State private var animateNumbers = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xs) {
            // Animated balance
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatBalance(Int64(displayedBalance)))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [OlasDesign.Colors.text, OlasDesign.Colors.text.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .contentTransition(.numericText())
                
                Text("sats")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
            .scaleEffect(animateNumbers ? 1 : 0.8)
            .opacity(animateNumbers ? 1 : 0)
            
            // USD value with shimmer effect
            if let price = btcPrice {
                let usdValue = Double(balance) * price / 100_000_000
                ShimmerText(
                    text: "≈ $\(String(format: "%.2f", usdValue)) USD",
                    font: .system(size: 18, weight: .medium, design: .rounded),
                    color: OlasDesign.Colors.textTertiary
                )
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                displayedBalance = Double(balance)
                animateNumbers = true
            }
        }
        .onChange(of: balance) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                displayedBalance = Double(newValue)
            }
        }
    }
    
    private func formatBalance(_ balance: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
}

// MARK: - Shimmer Text
struct ShimmerText: View {
    let text: String
    let font: Font
    let color: Color
    @State private var shimmerOffset: CGFloat = -1
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.5),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.3)
                    .offset(x: shimmerOffset * (geometry.size.width * 1.3))
                    .opacity(shimmerOffset > -0.5 && shimmerOffset < 1.5 ? 1 : 0)
                }
                .mask(
                    Text(text)
                        .font(font)
                )
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 2.5)
                    .repeatForever(autoreverses: false)
                    .delay(1)
                ) {
                    shimmerOffset = 1.5
                }
            }
    }
}

// MARK: - Floating Action Button
struct FloatingActionButton: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let action: () -> Void
    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0.5
    
    var body: some View {
        Button(action: {
            // Ripple effect
            withAnimation(.easeOut(duration: 0.6)) {
                rippleScale = 2
                rippleOpacity = 0
            }
            
            // Reset ripple
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                rippleScale = 0
                rippleOpacity = 0.5
            }
            
            OlasDesign.Haptic.impact(.medium)
            action()
        }) {
            VStack(spacing: OlasDesign.Spacing.xs) {
                ZStack {
                    // Ripple effect
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .scaleEffect(rippleScale)
                        .opacity(rippleOpacity)
                    
                    // Main button
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(
                            color: gradient.first?.opacity(0.4) ?? Color.clear,
                            radius: isPressed ? 5 : 10,
                            x: 0,
                            y: isPressed ? 2 : 5
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(isPressed ? 10 : 0))
                }
                .scaleEffect(isPressed ? 0.95 : 1)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OlasDesign.Colors.text)
                    .opacity(isPressed ? 0.8 : 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1)
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
}

// MARK: - Mint Allocation Chart
struct MintAllocationChart: View {
    let mintDistribution: [(mint: String, balance: Int, percentage: Double)]
    let mintColors: [Color]
    @State private var animationProgress: Double = 0
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            // Circular chart
            ZStack {
                // Background circle
                Circle()
                    .stroke(OlasDesign.Colors.divider, lineWidth: 2)
                    .frame(width: 180, height: 180)
                
                // Mint segments
                ForEach(Array(mintDistribution.enumerated()), id: \.offset) { index, item in
                    MintSegment(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        color: mintColors[index % mintColors.count],
                        animationProgress: animationProgress
                    )
                }
                
                // Center info
                VStack(spacing: 4) {
                    Text("\(mintDistribution.count)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(OlasDesign.Colors.text)
                    
                    Text("Mints")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                }
                .scaleEffect(animationProgress)
                .opacity(animationProgress)
            }
            
            // Legend with animated bars
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                ForEach(Array(mintDistribution.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: OlasDesign.Spacing.sm) {
                        // Color indicator
                        RoundedRectangle(cornerRadius: 4)
                            .fill(mintColors[index % mintColors.count])
                            .frame(width: 16, height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        
                        // Mint name
                        Text(item.mint)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(OlasDesign.Colors.text)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Percentage bar
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OlasDesign.Colors.divider.opacity(0.3))
                                .frame(width: 50, height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(mintColors[index % mintColors.count])
                                .frame(width: 50 * item.percentage / 100 * animationProgress, height: 4)
                        }
                        
                        // Amount
                        Text("\(String(format: "%.1f", item.percentage))%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(OlasDesign.Colors.textSecondary)
                            .opacity(animationProgress)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1, dampingFraction: 0.8).delay(0.2)) {
                animationProgress = 1
            }
        }
    }
    
    private func startAngle(for index: Int) -> Angle {
        guard !mintDistribution.isEmpty else { return .zero }
        var angle: Double = -90
        for i in 0..<index {
            angle += mintDistribution[i].percentage * 3.6
        }
        return .degrees(angle)
    }
    
    private func endAngle(for index: Int) -> Angle {
        guard !mintDistribution.isEmpty else { return .zero }
        var angle: Double = -90
        for i in 0...index {
            angle += mintDistribution[i].percentage * 3.6
        }
        return .degrees(angle)
    }
}

// MARK: - Mint Segment
struct MintSegment: View {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    let animationProgress: Double
    
    var body: some View {
        Circle()
            .trim(from: 0, to: animationProgress)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 30,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .rotationEffect(startAngle)
            .frame(width: 160, height: 160)
            .mask(
                Circle()
                    .trim(from: 0, to: (endAngle.degrees - startAngle.degrees) / 360)
                    .stroke(style: StrokeStyle(lineWidth: 30))
                    .frame(width: 160, height: 160)
            )
    }
}

// MARK: - Premium Button
struct PremiumActionButton: View {
    let title: String
    let icon: String?
    let gradient: [Color]
    let action: () -> Void
    let isLoading: Bool
    
    @State private var isPressed = false
    @State private var shimmerOffset: CGFloat = -1
    
    init(
        title: String,
        icon: String? = nil,
        gradient: [Color] = OlasDesign.Colors.primaryGradient,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            if !isLoading {
                OlasDesign.Haptic.impact(.medium)
                action()
            }
        }) {
            ZStack {
                // Background with gradient
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        // Shimmer effect
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 60)
                        .offset(x: shimmerOffset * 200)
                        .mask(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                        )
                    )
                
                // Content
                HStack(spacing: OlasDesign.Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        if let icon = icon {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .medium))
                        }
                        
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, OlasDesign.Spacing.xl)
                .padding(.vertical, OlasDesign.Spacing.md)
            }
            .scaleEffect(isPressed ? 0.95 : 1)
            .shadow(
                color: gradient.first?.opacity(0.4) ?? Color.clear,
                radius: isPressed ? 5 : 10,
                x: 0,
                y: isPressed ? 2 : 5
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .onAppear {
            withAnimation(
                .linear(duration: 3)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 1
            }
        }
    }
}