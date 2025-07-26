import SwiftUI

struct EnhancedTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    @State private var animatingTab: ContentView.Tab?
    @State private var tabWidths: [ContentView.Tab: CGFloat] = [:]
    @State private var tabOffsets: [ContentView.Tab: CGFloat] = [:]
    @State private var bubbleOffset: CGFloat = 0
    @State private var bubbleWidth: CGFloat = 60
    @State private var showTabLabels = true
    @Namespace private var animation
    
    // Haptic feedback
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Blurred background with gradient
                ZStack {
                    // Base blur
                    VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                    
                    // Gradient overlay
                    LinearGradient(
                        colors: [
                            Color.ds.background.opacity(0.95),
                            Color.ds.background.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Top border with glow
                    VStack {
                        LinearGradient(
                            colors: [
                                Color.ds.primary.opacity(0.3),
                                Color.ds.primary.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 1)
                        .blur(radius: 0.5)
                        
                        Spacer()
                    }
                }
                .frame(height: 88)
                .mask(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill()
                        .frame(height: 88)
                )
                
                // Dynamic selection bubble
                if let offset = tabOffsets[selectedTab] {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.ds.primary.opacity(0.15),
                                    Color.ds.primary.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.ds.primary.opacity(0.3),
                                            Color.ds.primary.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: bubbleWidth, height: 52)
                        .offset(x: offset, y: -24)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.2), value: selectedTab)
                }
                
                // Tab items
                HStack(spacing: 0) {
                    ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            animatingTab: animatingTab,
                            showLabel: showTabLabels,
                            namespace: animation
                        )
                        .frame(maxWidth: .infinity)
                        .background(
                            GeometryReader { itemGeometry in
                                Color.clear
                                    .onAppear {
                                        let frame = itemGeometry.frame(in: .named("tabBar"))
                                        tabOffsets[tab] = frame.midX - geometry.size.width / 2
                                        tabWidths[tab] = frame.width
                                    }
                                    .onChange(of: geometry.size) { _, _ in
                                        let frame = itemGeometry.frame(in: .named("tabBar"))
                                        tabOffsets[tab] = frame.midX - geometry.size.width / 2
                                        tabWidths[tab] = frame.width
                                    }
                            }
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedTab != tab {
                                    impactMedium.impactOccurred()
                                    animatingTab = tab
                                    selectedTab = tab
                                    
                                    // Update bubble width based on selected tab
                                    updateBubbleWidth(for: tab)
                                    
                                    // Clear animation state
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        animatingTab = nil
                                    }
                                } else {
                                    // Double tap effect
                                    impactLight.impactOccurred()
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                        animatingTab = tab
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        animatingTab = nil
                                    }
                                }
                            }
                        }
                        .onLongPressGesture {
                            impactMedium.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showTabLabels.toggle()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 34)
                .coordinateSpace(name: "tabBar")
                
                // Floating orb effect at selection
                if let offset = tabOffsets[selectedTab] {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.ds.primary.opacity(0.3),
                                    Color.ds.primary.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)
                        .blur(radius: 10)
                        .offset(x: offset, y: -24)
                        .allowsHitTesting(false)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectedTab)
                }
            }
            .frame(height: 88)
        }
        .frame(height: 88)
        .onAppear {
            impactMedium.prepare()
            impactLight.prepare()
            updateBubbleWidth(for: selectedTab)
        }
    }
    
    private func updateBubbleWidth(for tab: ContentView.Tab) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch tab {
            case .home, .profile:
                bubbleWidth = 65
            case .feed, .library:
                bubbleWidth = 70
            case .discover:
                bubbleWidth = 75
            }
        }
    }
}

struct TabItem: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    let animatingTab: ContentView.Tab?
    let showLabel: Bool
    let namespace: Namespace.ID
    
    @State private var iconRotation: Double = 0
    @State private var iconScale: CGFloat = 1
    
    var body: some View {
        VStack(spacing: showLabel ? 6 : 0) {
            ZStack {
                // Background icon (for smooth transitions)
                Image(systemName: tab.icon)
                    .font(.system(size: 24, weight: .medium))
                    .opacity(isSelected ? 0 : 1)
                    .foregroundColor(.ds.textSecondary)
                
                // Filled icon with animations
                Image(systemName: tab.filledIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                    .foregroundColor(.ds.primary)
                    .rotationEffect(.degrees(iconRotation))
                    .scaleEffect(iconScale)
            }
            .frame(width: 28, height: 28)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            
            if showLabel {
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .ds.primary : .ds.textSecondary)
                    .transition(.asymmetric(
                        insertion: .push(from: .bottom).combined(with: .opacity),
                        removal: .push(from: .top).combined(with: .opacity)
                    ))
            }
        }
        .scaleEffect(animatingTab == tab ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: animatingTab)
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                // Animate icon when selected
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    iconScale = 1.2
                    iconRotation = 10
                }
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                    iconScale = 1.0
                    iconRotation = 0
                }
            }
        }
    }
}

// Visual effect blur view
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

#Preview {
    ZStack {
        // Background content
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        // Tab bar at bottom
        VStack {
            Spacer()
            EnhancedTabBar(selectedTab: .constant(.home))
        }
    }
}