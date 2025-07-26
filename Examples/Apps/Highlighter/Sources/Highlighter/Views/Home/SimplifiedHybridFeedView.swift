import SwiftUI
import NDKSwift

// Make NDKEvent conform to Identifiable for SwiftUI usage
extension NDKEvent: Identifiable {}

struct SimplifiedHybridFeedView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dataManager = HomeDataManager()
    @State private var selectedSection = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var headerOpacity: Double = 1
    @State private var showLiveIndicator = false
    @State private var pulseAnimation = false
    
    // Dynamic gradient colors that shift based on time of day
    private var gradientColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: // Morning
            return [Color(hex: "FFE5B4"), Color(hex: "FFD700").opacity(0.3)]
        case 12..<17: // Afternoon
            return [Color(hex: "87CEEB").opacity(0.3), Color(hex: "4682B4").opacity(0.2)]
        case 17..<21: // Evening
            return [Color(hex: "FF6B6B").opacity(0.3), Color(hex: "FF8E53").opacity(0.2)]
        default: // Night
            return [Color(hex: "2C3E50").opacity(0.3), Color(hex: "34495E").opacity(0.2)]
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Animated gradient background
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .opacity(0.3)
                .animation(.easeInOut(duration: 3), value: gradientColors)
                
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Parallax header with live indicator
                            headerView
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .offset(y: scrollOffset * 0.5)
                                .opacity(headerOpacity)
                                .id("header")
                            
                            // Live activity indicator
                            if showLiveIndicator {
                                LiveActivityBar()
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)
                                    .transition(.asymmetric(
                                        insertion: .push(from: .top).combined(with: .opacity),
                                        removal: .push(from: .bottom).combined(with: .opacity)
                                    ))
                            }
                            
                            VStack(spacing: 32) {
                                // Featured Highlights with enhanced carousel
                                if !dataManager.userHighlights.isEmpty {
                                    enhancedCarouselSection(
                                        title: "Featured Highlights",
                                        subtitle: "Top highlights from your network",
                                        items: dataManager.userHighlights,
                                        icon: "sparkle"
                                    ) { highlight in
                                        EnhancedHighlightCard(highlight: highlight)
                                    }
                                } else {
                                    // Loading state with skeleton UI
                                    carouselLoadingState(title: "Featured Highlights")
                                }
                                
                                // Active Discussions with real-time indicator
                                if !dataManager.discussions.isEmpty {
                                    enhancedDiscussionsSection
                                }
                                
                                // Trending Content with zap animations
                                if !dataManager.zappedArticles.isEmpty {
                                    enhancedCarouselSection(
                                        title: "Trending Now",
                                        subtitle: "Most zapped content",
                                        items: dataManager.zappedArticles,
                                        icon: "bolt.fill"
                                    ) { event in
                                        EnhancedTrendingCard(event: event)
                                    }
                                }
                            }
                            .padding(.top, 24)
                        }
                        .padding(.bottom, 100)
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                        })
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                        withAnimation(.easeOut(duration: 0.2)) {
                            headerOpacity = min(1.0, max(0.0, (50.0 + value) / 50.0))
                        }
                    }
                    .refreshable {
                        HapticManager.shared.impact(.medium)
                        await dataManager.refresh()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            dataManager.appState = appState
            // Animate live indicator after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showLiveIndicator = true
                }
            }
        }
        .task {
            await dataManager.startStreaming()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(GreetingFormatter.timeBasedGreeting())
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.ds.text)
                    
                    // Animated emoji based on time
                    Text(timeBasedEmoji)
                        .font(.system(size: 28))
                        .rotationEffect(.degrees(pulseAnimation ? 10 : -10))
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseAnimation)
                        .onAppear { pulseAnimation = true }
                }
                
                HStack(spacing: 6) {
                    Text(GreetingFormatter.formattedDate())
                        .font(.ds.footnote)
                        .foregroundColor(.ds.textSecondary)
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    
                    Text("Live")
                        .font(.ds.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Activity indicator
            ActivityRing()
                .frame(width: 48, height: 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var timeBasedEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "☀️"
        case 12..<17: return "🌤"
        case 17..<21: return "🌅"
        default: return "🌙"
        }
    }
    
    private func enhancedCarouselSection<Item: Identifiable, Content: View>(
        title: String,
        subtitle: String? = nil,
        items: [Item],
        icon: String? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.ds.primary)
                            .symbolEffect(.pulse)
                    }
                    
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.ds.text)
                }
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.ds.footnote)
                        .foregroundColor(.ds.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { item in
                        content(item)
                            .frame(width: 300)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4) // For shadows
            }
        }
    }
    
    private func carouselLoadingState(title: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.ds.text)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.ds.surfaceSecondary)
                            .frame(width: 300, height: 200)
                            .shimmer()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var enhancedDiscussionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.ds.primary)
                            .symbolEffect(.pulse)
                        
                        Text("Active Discussions")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.ds.text)
                    }
                    
                    Text("\(dataManager.discussions.count) conversations happening now")
                        .font(.ds.footnote)
                        .foregroundColor(.ds.textSecondary)
                }
                
                Spacer()
                
                // Real-time indicator
                PulsingDot()
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(dataManager.discussions.prefix(5), id: \.id) { event in
                    EnhancedDiscussionRow(event: event)
                    
                    if event.id != dataManager.discussions.prefix(5).last?.id {
                        Divider()
                            .background(Color.ds.divider)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.ds.surfaceSecondary)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
            )
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Enhanced Cards

struct EnhancedHighlightCard: View {
    let highlight: HighlightEvent
    @State private var isPressed = false
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color.ds.primary.opacity(0.15),
                        Color.ds.primary.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(alignment: .leading, spacing: 16) {
                    // Source info if available
                    if let url = highlight.url {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.ds.primary)
                            
                            Text(ContentFormatter.extractDomain(from: url))
                                .font(.ds.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.ds.primary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                    
                    // Quote text with stylish quotes
                    HStack(alignment: .top, spacing: 12) {
                        Text("\"")
                            .font(.system(size: 36, weight: .black, design: .serif))
                            .foregroundColor(.ds.primary.opacity(0.3))
                            .offset(y: -8)
                        
                        Text(highlight.content)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.ds.text)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                        
                        Spacer(minLength: 0)
                    }
                    
                    Spacer()
                    
                    // Footer with interactions
                    HStack {
                        // Time and author
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.ds.primary.opacity(0.2))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(PubkeyFormatter.formatForAvatar(highlight.author))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.ds.primary)
                                )
                            
                            Text(RelativeTimeFormatter.relativeTime(from: highlight.createdAt ?? Date()))
                                .font(.ds.caption)
                                .foregroundColor(.ds.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Interaction buttons
                        HStack(spacing: 16) {
                            InteractionButton(icon: "heart", count: Int.random(in: 5...50))
                            InteractionButton(icon: "bubble.right", count: Int.random(in: 0...20))
                            InteractionButton(icon: "bolt.fill", count: Int.random(in: 100...1000), color: .orange)
                        }
                    }
                }
                .padding(24)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
            .scaleEffect(isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
            if pressing {
                HapticManager.shared.impact(.light)
            }
        }, perform: {})
        .sheet(isPresented: $showingDetail) {
            HighlightDetailView(highlight: highlight)
        }
    }
}

struct EnhancedTrendingCard: View {
    let event: NDKEvent
    @State private var zapAnimation = false
    @State private var particleAnimation = false
    
    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.2),
                    Color.yellow.opacity(0.1)
                ],
                startPoint: zapAnimation ? .topLeading : .bottomTrailing,
                endPoint: zapAnimation ? .bottomTrailing : .topLeading
            )
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: zapAnimation)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Animated zap icon
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.3)],
                                    center: .center,
                                    startRadius: 5,
                                    endRadius: 25
                                )
                            )
                            .frame(width: 56, height: 56)
                            .scaleEffect(zapAnimation ? 1.1 : 1.0)
                        
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .rotationEffect(.degrees(zapAnimation ? 10 : -10))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lightning Zapped")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.ds.text)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                            
                            Text("\(Int.random(in: 1000...50000)) sats")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                }
                
                Text(event.content.prefix(100) + "...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.ds.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                // Engagement metrics
                HStack(spacing: 20) {
                    MetricPill(icon: "eye", value: "\(Int.random(in: 100...1000))")
                    MetricPill(icon: "arrow.2.squarepath", value: "\(Int.random(in: 10...100))")
                    MetricPill(icon: "heart.fill", value: "\(Int.random(in: 50...500))")
                }
            }
            .padding(20)
            
            // Particle effects
            if particleAnimation {
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                        .offset(
                            x: particleAnimation ? CGFloat.random(in: -150...150) : 0,
                            y: particleAnimation ? CGFloat.random(in: -100...100) : 0
                        )
                        .opacity(particleAnimation ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.5)
                            .delay(Double(index) * 0.1)
                            .repeatForever(autoreverses: false),
                            value: particleAnimation
                        )
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.orange.opacity(0.2), radius: 16, y: 8)
        .onAppear {
            zapAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                particleAnimation = true
            }
        }
    }
}

struct EnhancedDiscussionRow: View {
    let event: NDKEvent
    @State private var author: NDKUserProfile?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                AsyncProfileImage(pubkey: event.pubkey, size: 44)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.ds.background, lineWidth: 2)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(author?.displayName ?? PubkeyFormatter.formatCompact(event.pubkey))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.ds.text)
                    
                    Text("·")
                        .foregroundColor(.ds.textTertiary)
                    
                    Text(RelativeTimeFormatter.shortRelativeTime(from: event.createdAt))
                        .font(.ds.caption)
                        .foregroundColor(.ds.textTertiary)
                    
                    Spacer()
                    
                    if Bool.random() {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
                
                Text(event.content)
                    .font(.system(size: 14))
                    .foregroundColor(.ds.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Engagement row
                HStack(spacing: 20) {
                    EngagementButton(icon: "bubble.right", count: Int.random(in: 0...20))
                    EngagementButton(icon: "arrow.2.squarepath", count: Int.random(in: 0...10))
                    EngagementButton(icon: "heart", count: Int.random(in: 0...50))
                    EngagementButton(icon: "bolt.fill", count: Int.random(in: 0...1000), color: .orange)
                }
                .padding(.top, 4)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Supporting Components

struct LiveActivityBar: View {
    @State private var dots = [false, false, false]
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(dots[index] ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .delay(Double(index) * 0.2)
                            .repeatForever(autoreverses: true),
                            value: dots[index]
                        )
                }
                
                Text("Live feed updating")
                    .font(.ds.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
            
            Spacer()
        }
        .onAppear {
            dots = [true, true, true]
        }
    }
}

struct ActivityRing: View {
    @State private var progress: CGFloat = 0.75
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ds.surfaceSecondary, lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.ds.primary, .ds.primary.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(rotation))
                .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotation)
            
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.ds.primary)
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.ds.textSecondary)
            }
        }
        .onAppear {
            rotation = 360
        }
    }
}

struct PulsingDot: View {
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            
            Circle()
                .stroke(Color.green, lineWidth: 1)
                .frame(width: 16, height: 16)
                .scaleEffect(scale)
                .opacity(opacity)
                .animation(
                    .easeOut(duration: 1)
                    .repeatForever(autoreverses: false),
                    value: scale
                )
        }
        .onAppear {
            scale = 2
            opacity = 0
        }
    }
}

struct InteractionButton: View {
    let icon: String
    let count: Int
    var color: Color = .ds.textSecondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
            if count > 0 {
                Text(formatCount(count))
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundColor(color)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)k"
        }
        return "\(count)"
    }
}

struct EngagementButton: View {
    let icon: String
    let count: Int
    var color: Color = .ds.textSecondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundColor(color)
    }
}

struct MetricPill: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.ds.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.ds.surfaceSecondary)
        )
    }
}

struct AsyncProfileImage: View {
    let pubkey: String
    let size: CGFloat
    
    var body: some View {
        // Placeholder implementation - would load actual profile image
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.ds.primary.opacity(0.6),
                        Color.ds.secondary.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(PubkeyFormatter.formatForAvatar(pubkey))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}


#Preview {
    SimplifiedHybridFeedView()
        .environmentObject(AppState())
}