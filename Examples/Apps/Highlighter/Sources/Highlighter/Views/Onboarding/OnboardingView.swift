import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var animateElements = false
    @State private var particleAnimation = false
    @Binding var hasCompletedOnboarding: Bool
    @Namespace private var namespace
    
    let pages = OnboardingPage.allPages
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            OnboardingGradientBackground(currentPage: currentPage)
            
            // Floating particles
            FloatingParticlesView(animate: $particleAnimation)
                .opacity(0.6)
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentPage = pages.count - 1
                            }
                        }
                        .font(.ds.bodyMedium)
                        .foregroundColor(.white.opacity(0.8))
                        .padding()
                        .transition(.opacity)
                    }
                }
                .frame(height: 60)
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(
                            page: pages[index],
                            namespace: namespace,
                            isActive: currentPage == index
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.8), value: currentPage)
                
                // Bottom controls
                VStack(spacing: 32) {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            OnboardingPageIndicator(
                                isActive: currentPage == index,
                                index: index,
                                currentPage: currentPage
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    currentPage = index
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Action button
                    OnboardingActionButton(
                        title: currentPage == pages.count - 1 ? "Get Started" : "Next",
                        isLastPage: currentPage == pages.count - 1,
                        action: {
                            if currentPage == pages.count - 1 {
                                completeOnboarding()
                            } else {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    currentPage += 1
                                    HapticManager.shared.impact(.light)
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 40)
                }
                .padding(.bottom, 50)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animateElements = true
                particleAnimation = true
            }
        }
        .onChange(of: currentPage) { _ in
            HapticManager.shared.impact(.light)
        }
    }
    
    private func completeOnboarding() {
        HapticManager.shared.notification(.success)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let features: [Feature]
    
    struct Feature {
        let icon: String
        let text: String
    }
    
    static let allPages = [
        OnboardingPage(
            title: "Welcome to\nHighlighter",
            subtitle: "Your personal knowledge companion for the decentralized web",
            icon: "highlighter",
            iconColor: .orange,
            features: [
                Feature(icon: "quote.bubble.fill", text: "Capture insights from anywhere"),
                Feature(icon: "sparkles", text: "AI-powered smart highlights"),
                Feature(icon: "person.2.fill", text: "Share with your community")
            ]
        ),
        OnboardingPage(
            title: "Highlight\nWhat Matters",
            subtitle: "Save and organize the best content from articles, notes, and conversations",
            icon: "text.quote",
            iconColor: .purple,
            features: [
                Feature(icon: "wand.and.stars", text: "One-tap highlighting"),
                Feature(icon: "folder.fill", text: "Smart collections"),
                Feature(icon: "magnifyingglass", text: "Powerful search")
            ]
        ),
        OnboardingPage(
            title: "Build Your\nKnowledge Graph",
            subtitle: "Connect ideas, discover patterns, and grow your understanding",
            icon: "brain",
            iconColor: .blue,
            features: [
                Feature(icon: "link", text: "Connect related highlights"),
                Feature(icon: "chart.xyaxis.line", text: "Visualize your learning"),
                Feature(icon: "lightbulb.fill", text: "Surface insights")
            ]
        ),
        OnboardingPage(
            title: "Join the\nConversation",
            subtitle: "Share highlights, discuss ideas, and learn from others",
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: .green,
            features: [
                Feature(icon: "heart.fill", text: "Support great content"),
                Feature(icon: "bolt.fill", text: "Zap creators directly"),
                Feature(icon: "globe", text: "Decentralized & open")
            ]
        )
    ]
}

// MARK: - Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    let namespace: Namespace.ID
    let isActive: Bool
    @State private var animateIcon = false
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 48) {
            Spacer()
            
            // Animated icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(page.iconColor.opacity(0.3))
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .scaleEffect(animateIcon ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 3)
                        .repeatForever(autoreverses: true),
                        value: animateIcon
                    )
                
                // Icon background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                page.iconColor.opacity(0.3),
                                page.iconColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                // Main icon
                Image(systemName: page.icon)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(animateIcon ? 5 : -5))
                    .animation(
                        .easeInOut(duration: 4)
                        .repeatForever(autoreverses: true),
                        value: animateIcon
                    )
            }
            .scaleEffect(isActive ? 1.0 : 0.8)
            .opacity(isActive ? 1.0 : 0.5)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isActive)
            
            // Content
            VStack(spacing: 24) {
                // Title
                Text(page.title)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                
                // Subtitle
                Text(page.subtitle)
                    .font(.ds.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.6).delay(0.1), value: animateContent)
                
                // Features
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(page.features.enumerated()), id: \.offset) { index, feature in
                        HStack(spacing: 16) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 20))
                                .foregroundColor(page.iconColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(page.iconColor.opacity(0.2))
                                )
                            
                            Text(feature.text)
                                .font(.ds.callout)
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                        }
                        .opacity(animateContent ? 1 : 0)
                        .offset(x: animateContent ? 0 : -20)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7)
                            .delay(Double(index) * 0.1 + 0.2),
                            value: animateContent
                        )
                    }
                }
                .padding(.horizontal, 60)
            }
            
            Spacer()
        }
        .onAppear {
            if isActive {
                animateIcon = true
                withAnimation {
                    animateContent = true
                }
            }
        }
        .onChange(of: isActive) { active in
            if active {
                animateIcon = true
                withAnimation {
                    animateContent = true
                }
            } else {
                animateIcon = false
                animateContent = false
            }
        }
    }
}

// MARK: - Components

struct OnboardingGradientBackground: View {
    let currentPage: Int
    
    private var gradientColors: [Color] {
        switch currentPage {
        case 0: return [Color.orange.opacity(0.6), Color.pink.opacity(0.4)]
        case 1: return [Color.purple.opacity(0.6), Color.blue.opacity(0.4)]
        case 2: return [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)]
        case 3: return [Color.green.opacity(0.6), Color.teal.opacity(0.4)]
        default: return [Color.orange.opacity(0.6), Color.pink.opacity(0.4)]
        }
    }
    
    var body: some View {
        LinearGradient(
            colors: gradientColors + [Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 0.8), value: currentPage)
        .ignoresSafeArea()
    }
}

struct OnboardingPageIndicator: View {
    let isActive: Bool
    let index: Int
    let currentPage: Int
    
    private var shouldAnimate: Bool {
        abs(currentPage - index) <= 1
    }
    
    var body: some View {
        Capsule()
            .fill(isActive ? Color.white : Color.white.opacity(0.3))
            .frame(width: isActive ? 32 : 8, height: 8)
            .scaleEffect(shouldAnimate ? 1.0 : 0.8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

struct OnboardingActionButton: View {
    let title: String
    let isLastPage: Bool
    let action: () -> Void
    @State private var isPressed = false
    @State private var shimmerAnimation = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Background gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                isLastPage ? Color.orange : Color.white.opacity(0.2),
                                isLastPage ? Color.orange.opacity(0.8) : Color.white.opacity(0.1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                // Shimmer effect for last page
                if isLastPage {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerAnimation ? 200 : -200)
                        .animation(
                            .linear(duration: 1.5)
                            .repeatForever(autoreverses: false),
                            value: shimmerAnimation
                        )
                        .mask(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                
                // Button text
                Text(title)
                    .font(.ds.bodyMedium)
                    .foregroundColor(isLastPage ? .white : .white.opacity(0.9))
            }
            .frame(height: 56)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                action()
            }
        )
        .shadow(
            color: isLastPage ? Color.orange.opacity(0.3) : Color.white.opacity(0.1),
            radius: 20,
            y: 10
        )
        .onAppear {
            if isLastPage {
                shimmerAnimation = true
            }
        }
    }
}

struct FloatingParticlesView: View {
    @Binding var animate: Bool
    let particleCount = 20
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<particleCount, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: CGFloat.random(in: 2...6))
                    .position(
                        x: CGFloat.random(in: 0...geometry.size.width),
                        y: animate ? -10 : geometry.size.height + 10
                    )
                    .animation(
                        .linear(duration: Double.random(in: 10...20))
                        .repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.5),
                        value: animate
                    )
            }
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}