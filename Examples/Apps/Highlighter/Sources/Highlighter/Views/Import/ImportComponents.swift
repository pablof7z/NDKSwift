import SwiftUI
import UniformTypeIdentifiers

// MARK: - Ripple Button

struct RippleButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var ripples: [Ripple] = []
    @State private var isPressed = false
    
    struct Ripple: Identifiable {
        let id = UUID()
        let position: CGPoint
        let startTime = Date()
    }
    
    var body: some View {
        GeometryReader { geometry in
            Button(action: {
                HapticManager.shared.impact(.medium)
                action()
            }) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: .ds.medium, style: .continuous)
                        .fill(Color.orange)
                        .scaleEffect(isPressed ? 0.98 : 1)
                    
                    // Ripples
                    ForEach(ripples) { ripple in
                        RippleView(
                            position: ripple.position,
                            startTime: ripple.startTime,
                            size: geometry.size
                        )
                    }
                    
                    // Content
                    HStack(spacing: .ds.small) {
                        Image(systemName: icon)
                        Text(title)
                    }
                    .font(.ds.bodyMedium)
                    .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = pressing
                }
            } perform: {}
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newRipple = Ripple(position: value.location)
                        ripples.append(newRipple)
                        
                        // Remove old ripples
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            ripples.removeAll { $0.id == newRipple.id }
                        }
                    }
            )
        }
        .frame(height: 50)
    }
}

struct RippleView: View {
    let position: CGPoint
    let startTime: Date
    let size: CGSize
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0.5
    
    var body: some View {
        Circle()
            .fill(Color.white.opacity(opacity))
            .frame(width: 50, height: 50)
            .scaleEffect(scale)
            .position(position)
            .onAppear {
                let maxScale = max(size.width, size.height) / 25
                withAnimation(.easeOut(duration: 0.8)) {
                    scale = maxScale
                    opacity = 0
                }
            }
    }
}

// MARK: - Animated Mesh Background

struct AnimatedMeshBackground: View {
    @State private var phase: Double = 0
    @State private var colors: [Color] = [.orange.opacity(0.3), .purple.opacity(0.3), .blue.opacity(0.3)]
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Create mesh gradient effect
                for y in stride(from: 0, to: size.height, by: 50) {
                    for x in stride(from: 0, to: size.width, by: 50) {
                        let offsetX = sin(time * 0.5 + Double(x) * 0.01) * 20
                        let offsetY = cos(time * 0.5 + Double(y) * 0.01) * 20
                        
                        let color = colors[Int(x + y) % colors.count]
                        
                        context.fill(
                            Circle().path(in: CGRect(
                                x: x + offsetX,
                                y: y + offsetY,
                                width: 80,
                                height: 80
                            )),
                            with: .radialGradient(
                                Gradient(colors: [color, color.opacity(0)]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                    }
                }
            }
        }
        .blur(radius: 30)
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    
    struct ConfettiParticle: Identifiable {
        let id = UUID()
        let color: Color
        let size: CGFloat
        let shape: ConfettiShape
        var position: CGPoint
        var velocity: CGVector
        var rotation: Double
        var rotationSpeed: Double
        
        enum ConfettiShape: CaseIterable {
            case circle, square, triangle
        }
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let currentTime = timeline.date.timeIntervalSinceReferenceDate
                
                for particle in particles {
                    context.save()
                    context.translateBy(x: particle.position.x, y: particle.position.y)
                    context.rotate(by: .degrees(particle.rotation))
                    
                    let rect = CGRect(
                        x: -particle.size / 2,
                        y: -particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )
                    
                    switch particle.shape {
                    case .circle:
                        context.fill(Circle().path(in: rect), with: .color(particle.color))
                    case .square:
                        context.fill(Rectangle().path(in: rect), with: .color(particle.color))
                    case .triangle:
                        let path = Path { path in
                            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                            path.closeSubpath()
                        }
                        context.fill(path, with: .color(particle.color))
                    }
                    
                    context.restore()
                }
            }
        }
        .onAppear {
            createParticles()
        }
        .onChange(of: particles.count) { _, _ in
            updateParticles()
        }
    }
    
    private func createParticles() {
        let colors: [Color] = [.orange, .yellow, .purple, .blue, .green, .pink]
        
        for _ in 0..<100 {
            let particle = ConfettiParticle(
                color: colors.randomElement()!,
                size: CGFloat.random(in: 5...15),
                shape: ConfettiParticle.ConfettiShape.allCases.randomElement()!,
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -50
                ),
                velocity: CGVector(
                    dx: CGFloat.random(in: -100...100),
                    dy: CGFloat.random(in: 200...400)
                ),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -180...180)
            )
            particles.append(particle)
        }
        
        // Start physics simulation
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            updateParticles()
        }
    }
    
    private func updateParticles() {
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.dx * 0.016
            particles[i].position.y += particles[i].velocity.dy * 0.016
            particles[i].velocity.dy += 500 * 0.016 // gravity
            particles[i].rotation += particles[i].rotationSpeed * 0.016
            
            // Remove particles that fall off screen
            if particles[i].position.y > UIScreen.main.bounds.height + 50 {
                particles.remove(at: i)
                break
            }
        }
    }
}

// MARK: - Smart Highlight Suggestions

struct SmartHighlightSuggestions: View {
    let content: ExtractedContent
    let onComplete: ([SuggestedHighlight]) -> Void
    @State private var suggestions: [SuggestedHighlight]
    @State private var selectedCount: Int = 0
    @State private var showAIExplanation = false
    @State private var filterImportance: HighlightImportance?
    @Environment(\.dismiss) var dismiss
    
    init(content: ExtractedContent, onComplete: @escaping ([SuggestedHighlight]) -> Void) {
        self.content = content
        self.onComplete = onComplete
        self._suggestions = State(initialValue: content.suggestedHighlights)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.ds.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: .ds.large) {
                        // Header with stats
                        suggestionHeader
                        
                        // Filter chips
                        filterChips
                        
                        // Suggestions list
                        LazyVStack(spacing: .ds.medium) {
                            ForEach(filteredSuggestions) { suggestion in
                                SuggestionCard(
                                    suggestion: suggestion,
                                    onToggle: { toggleSuggestion(suggestion) }
                                )
                                .transition(.asymmetric(
                                    insertion: .push(from: .trailing).combined(with: .opacity),
                                    removal: .push(from: .leading).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                    .padding(.horizontal, .ds.screenPadding)
                    .padding(.bottom, 100)
                }
                
                // Floating action button
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        ImportFloatingActionButton(
                            selectedCount: selectedCount,
                            action: {
                                onComplete(suggestions.filter { $0.isSelected })
                            }
                        )
                    }
                    .padding(.ds.screenPadding)
                }
            }
            .navigationTitle("AI Suggestions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAIExplanation = true
                    }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showAIExplanation) {
            AIExplanationSheet()
        }
        .onChange(of: suggestions) { _, _ in
            selectedCount = suggestions.filter { $0.isSelected }.count
        }
    }
    
    @ViewBuilder
    private var suggestionHeader: some View {
        VStack(spacing: .ds.medium) {
            HStack {
                VStack(alignment: .leading, spacing: .ds.micro) {
                    Text("Found \(content.suggestedHighlights.count) highlights")
                        .font(.ds.title2)
                        .foregroundColor(.ds.text)
                    
                    Text("From \"\(content.title)\"")
                        .font(.ds.body)
                        .foregroundColor(.ds.textSecondary)
                }
                
                Spacer()
                
                // Animated stats circle
                ZStack {
                    Circle()
                        .stroke(Color.ds.textTertiary.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(selectedCount) / CGFloat(suggestions.count))
                        .stroke(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectedCount)
                    
                    Text("\(selectedCount)")
                        .font(.ds.headline)
                        .foregroundColor(.ds.text)
                        .contentTransition(.numericText())
                }
            }
            
            // Quick actions
            HStack(spacing: .ds.small) {
                Button(action: selectAll) {
                    Label("Select All", systemImage: "checkmark.square.fill")
                        .font(.ds.footnoteMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: deselectAll) {
                    Label("Deselect All", systemImage: "square")
                        .font(.ds.footnoteMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(.ds.medium)
        .background(Color.ds.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: .ds.large, style: .continuous))
    }
    
    @ViewBuilder
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .ds.small) {
                ForEach([HighlightImportance.high, .medium, .low], id: \.self) { importance in
                    FilterChip(
                        importance: importance,
                        isSelected: filterImportance == importance,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                filterImportance = filterImportance == importance ? nil : importance
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var filteredSuggestions: [SuggestedHighlight] {
        if let filter = filterImportance {
            return suggestions.filter { $0.importance == filter }
        }
        return suggestions
    }
    
    private func toggleSuggestion(_ suggestion: SuggestedHighlight) {
        if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                suggestions[index].isSelected.toggle()
            }
            HapticManager.shared.impact(.light)
        }
    }
    
    private func selectAll() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            for i in suggestions.indices {
                suggestions[i].isSelected = true
            }
        }
        HapticManager.shared.impact(.medium)
    }
    
    private func deselectAll() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            for i in suggestions.indices {
                suggestions[i].isSelected = false
            }
        }
        HapticManager.shared.impact(.medium)
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let suggestion: SuggestedHighlight
    let onToggle: () -> Void
    @State private var isExpanded = false
    @State private var glowAnimation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: .ds.small) {
            HStack(alignment: .top) {
                // Selection checkbox with animation
                Button(action: onToggle) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(suggestion.isSelected ? suggestion.importance.color : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(suggestion.isSelected ? Color.clear : Color.ds.textTertiary, lineWidth: 2)
                            )
                            .frame(width: 24, height: 24)
                        
                        if suggestion.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: suggestion.isSelected)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: .ds.micro) {
                    // Importance indicator
                    HStack(spacing: .ds.micro) {
                        Image(systemName: suggestion.importance.icon)
                            .font(.caption)
                            .foregroundColor(suggestion.importance.color)
                        
                        Text("\(Int(suggestion.confidence * 100))% confidence")
                            .font(.ds.micro)
                            .foregroundColor(.ds.textSecondary)
                    }
                    
                    // Highlight text
                    Text(suggestion.text)
                        .font(.ds.body)
                        .foregroundColor(.ds.text)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !isExpanded && suggestion.text.count > 150 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded = true
                            }
                        }) {
                            Text("Show more")
                                .font(.ds.caption)
                                .foregroundColor(.ds.primary)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Context preview (when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: .ds.small) {
                    Divider()
                    
                    Label("Context", systemImage: "text.alignleft")
                        .font(.ds.footnoteMedium)
                        .foregroundColor(.ds.textSecondary)
                    
                    Text(getContextPreview())
                        .font(.ds.caption)
                        .foregroundColor(.ds.textTertiary)
                        .lineLimit(4)
                        .padding(.ds.small)
                        .background(Color.ds.surfaceTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: .ds.small))
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.ds.medium)
        .background(
            RoundedRectangle(cornerRadius: .ds.medium, style: .continuous)
                .fill(suggestion.isSelected ? suggestion.importance.color.opacity(0.05) : Color.ds.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: .ds.medium, style: .continuous)
                        .stroke(
                            suggestion.isSelected ? suggestion.importance.color.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .overlay(
            // Glow effect for high importance
            suggestion.importance == .high && glowAnimation ?
                RoundedRectangle(cornerRadius: .ds.medium, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [suggestion.importance.color.opacity(0.5), suggestion.importance.color.opacity(0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 4)
                : nil
        )
        .onAppear {
            if suggestion.importance == .high {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowAnimation = true
                }
            }
        }
    }
    
    private func getContextPreview() -> String {
        // Extract context around the highlight
        let contextLength = 200
        if let range = suggestion.context.range(of: suggestion.text) {
            let startIndex = suggestion.context.index(range.lowerBound, offsetBy: -min(100, suggestion.context.distance(from: suggestion.context.startIndex, to: range.lowerBound)))
            let endIndex = suggestion.context.index(range.upperBound, offsetBy: min(100, suggestion.context.distance(from: range.upperBound, to: suggestion.context.endIndex)))
            
            return "..." + String(suggestion.context[startIndex..<endIndex]) + "..."
        }
        return suggestion.context.prefix(contextLength) + "..."
    }
}

// MARK: - Supporting Components

struct FilterChip: View {
    let importance: HighlightImportance
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: .ds.micro) {
                Image(systemName: importance.icon)
                Text(String(describing: importance).capitalized)
            }
            .font(.ds.footnoteMedium)
            .foregroundColor(isSelected ? .white : importance.color)
            .padding(.horizontal, .ds.base)
            .padding(.vertical, .ds.micro)
            .background(
                Capsule()
                    .fill(isSelected ? importance.color : importance.color.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(importance.color, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ImportFloatingActionButton: View {
    let selectedCount: Int
    let action: () -> Void
    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.medium)
            action()
        }) {
            HStack(spacing: .ds.small) {
                Image(systemName: "checkmark.circle.fill")
                    .rotationEffect(.degrees(rotationAngle))
                Text("Import \(selectedCount) Highlights")
                    .fontWeight(.semibold)
            }
            .font(.ds.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, .ds.large)
            .padding(.vertical, .ds.base)
            .background(
                LinearGradient(
                    colors: [.orange, .orange.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
            .scaleEffect(isPressed ? 0.95 : 1)
            .opacity(selectedCount > 0 ? 1 : 0.5)
        }
        .disabled(selectedCount == 0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        } perform: {}
        .onChange(of: selectedCount) { _, _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                rotationAngle += 360
            }
        }
    }
}

// MARK: - AI Explanation Sheet

struct AIExplanationSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .ds.large) {
                    // Header illustration
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange.opacity(0.2), .orange.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "brain.filled.head.profile")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, .ds.large)
                    
                    Text("How AI Suggestions Work")
                        .font(.ds.title2)
                        .foregroundColor(.ds.text)
                    
                    VStack(alignment: .leading, spacing: .ds.medium) {
                        ExplanationRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Content Analysis",
                            description: "Our AI analyzes the entire document to understand context and themes."
                        )
                        
                        ExplanationRow(
                            icon: "brain",
                            title: "Smart Selection",
                            description: "Machine learning identifies the most insightful and quotable passages."
                        )
                        
                        ExplanationRow(
                            icon: "star.fill",
                            title: "Confidence Scoring",
                            description: "Each suggestion is scored based on relevance, clarity, and impact."
                        )
                        
                        ExplanationRow(
                            icon: "lock.fill",
                            title: "Privacy First",
                            description: "All processing happens locally. Your content never leaves your device."
                        )
                    }
                    
                    Text("The AI looks for key insights, memorable quotes, important facts, and thought-provoking ideas that align with the Highlighter community's interests.")
                        .font(.ds.caption)
                        .foregroundColor(.ds.textSecondary)
                        .padding()
                        .background(Color.ds.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: .ds.medium))
                }
                .padding(.horizontal, .ds.screenPadding)
                .padding(.bottom, .ds.large)
            }
            .navigationTitle("About AI Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExplanationRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: .ds.medium) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: .ds.micro) {
                Text(title)
                    .font(.ds.bodyMedium)
                    .foregroundColor(.ds.text)
                
                Text(description)
                    .font(.ds.caption)
                    .foregroundColor(.ds.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Additional Support Types

struct ParticleSystem {
    var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var velocity: CGVector
        var color: Color
        var size: CGFloat
        var lifetime: Double
    }
}

enum PopularSource: String, CaseIterable {
    case medium = "Medium"
    case substack = "Substack"
    case arxiv = "arXiv"
    case wikipedia = "Wikipedia"
    
    var icon: String {
        switch self {
        case .medium: return "m.circle.fill"
        case .substack: return "s.circle.fill"
        case .arxiv: return "a.circle.fill"
        case .wikipedia: return "w.circle.fill"
        }
    }
    
    var baseURL: String {
        switch self {
        case .medium: return "https://medium.com/"
        case .substack: return "https://substack.com/"
        case .arxiv: return "https://arxiv.org/"
        case .wikipedia: return "https://wikipedia.org/"
        }
    }
}

struct PopularSourceCard: View {
    let source: PopularSource
    let onSelect: (String) -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            onSelect(source.baseURL)
            HapticManager.shared.impact(.light)
        }) {
            VStack(spacing: .ds.small) {
                Text(source.icon)
                    .font(.system(size: 30))
                
                Text(source.rawValue)
                    .font(.ds.caption)
                    .foregroundColor(.ds.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.ds.base)
            .background(
                RoundedRectangle(cornerRadius: .ds.medium, style: .continuous)
                    .fill(isHovered ? Color.ds.surfaceTertiary : Color.ds.surfaceSecondary)
            )
            .scaleEffect(isHovered ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct ArticlePreview: View {
    let html: String
    
    var body: some View {
        // Simplified preview - in production, use WKWebView
        ScrollView {
            Text(stripHTML(html))
                .font(.ds.caption)
                .foregroundColor(.ds.text)
                .padding()
        }
        .background(Color.ds.surfaceSecondary)
    }
    
    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&[^;]+;", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TipsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .ds.small) {
            Label("Tips for Better Results", systemImage: "lightbulb.fill")
                .font(.ds.footnoteMedium)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: .ds.micro) {
                TipRow(text: "Hold your device steady")
                TipRow(text: "Ensure good lighting")
                TipRow(text: "Capture text at a straight angle")
                TipRow(text: "Avoid shadows and glare")
            }
        }
        .padding(.ds.medium)
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.1), .orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: .ds.medium, style: .continuous))
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: .ds.small) {
            Circle()
                .fill(Color.orange)
                .frame(width: 4, height: 4)
            
            Text(text)
                .font(.ds.caption)
                .foregroundColor(.ds.textSecondary)
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onCapture: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
                parent.onCapture(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}