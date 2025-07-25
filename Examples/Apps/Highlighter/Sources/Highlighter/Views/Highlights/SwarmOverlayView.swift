import SwiftUI
import NDKSwift

struct SwarmOverlayView: View {
    let text: String
    @ObservedObject var swarmManager: SwarmHighlightManager
    @State private var selectedHighlight: SwarmHighlight?
    @State private var popoverPosition: CGPoint = .zero
    @State private var glowAnimation = false
    @Namespace private var animation
    
    var body: some View {
        GeometryReader { geometry in
            SwarmTextView(
                text: text,
                swarmHighlights: swarmManager.findOverlappingHighlights(in: text),
                selectedHighlight: $selectedHighlight,
                popoverPosition: $popoverPosition,
                geometry: geometry
            )
        }
        .overlay(alignment: .topLeading) {
            if let highlight = selectedHighlight {
                SwarmPopover(
                    highlight: highlight,
                    position: popoverPosition,
                    onDismiss: { selectedHighlight = nil }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowAnimation = true
            }
        }
    }
}

struct SwarmTextView: UIViewRepresentable {
    let text: String
    let swarmHighlights: [(range: NSRange, highlight: SwarmHighlight)]
    @Binding var selectedHighlight: SwarmHighlight?
    @Binding var popoverPosition: CGPoint
    let geometry: GeometryProxy
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        textView.delegate = context.coordinator
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Base text styling
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        paragraphStyle.paragraphSpacing = 16
        
        attributedString.addAttributes([
            .font: UIFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ], range: NSRange(location: 0, length: text.count))
        
        // Apply swarm highlights with intensity-based styling
        for (range, highlight) in swarmHighlights {
            let intensity = highlight.intensity
            
            // Create gradient underline effect
            let underlineColor = UIColor.systemOrange.withAlphaComponent(0.3 + (intensity * 0.7))
            
            attributedString.addAttributes([
                .backgroundColor: UIColor.systemOrange.withAlphaComponent(0.05 + (intensity * 0.15)),
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
                .underlineColor: underlineColor,
                .strokeWidth: -0.5,
                .strokeColor: UIColor.systemOrange.withAlphaComponent(intensity * 0.3)
            ], range: range)
        }
        
        textView.attributedText = attributedString
        context.coordinator.parent = self
        context.coordinator.highlights = swarmHighlights
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SwarmTextView
        var highlights: [(range: NSRange, highlight: SwarmHighlight)] = []
        
        init(_ parent: SwarmTextView) {
            self.parent = parent
        }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            // Check if tap is on a highlight
            if let tappedHighlight = highlights.first(where: { NSLocationInRange(characterRange.location, $0.range) }) {
                // Calculate popover position
                if let position = textView.position(from: textView.beginningOfDocument, offset: characterRange.location) {
                    let rect = textView.caretRect(for: position)
                    let globalRect = textView.convert(rect, to: nil)
                    
                    DispatchQueue.main.async {
                        self.parent.selectedHighlight = tappedHighlight.highlight
                        self.parent.popoverPosition = CGPoint(
                            x: globalRect.midX,
                            y: globalRect.minY - 10
                        )
                        HapticManager.shared.impact(.light)
                    }
                }
            }
            return false
        }
    }
}

struct SwarmPopover: View {
    let highlight: SwarmHighlight
    let position: CGPoint
    let onDismiss: () -> Void
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(highlight.totalHighlighters) highlighters")
                            .font(.caption.weight(.medium))
                        
                        if highlight.totalZaps > 0 {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("\(highlight.totalZaps) zaps")
                                .font(.caption.weight(.medium))
                        }
                    }
                    
                    Text("\"\(highlight.text)\"")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Expanded details
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(highlight.highlights) { info in
                        SwarmHighlightRow(info: info)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.orange.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            // Glow effect
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.4),
                            Color.orange.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .blur(radius: 3)
        )
        .position(x: position.x, y: position.y)
        .onTapGesture {
            // Prevent dismissal when tapping inside
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        onDismiss()
                    }
                }
        )
    }
}

struct SwarmHighlightRow: View {
    let info: SwarmHighlight.HighlightInfo
    @State private var showZapAnimation = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Group {
                if let picture = info.profile?.picture {
                    AsyncImage(url: URL(string: picture)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                    }
                } else {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .overlay(
                            Text(String(info.profile?.name?.first ?? "?"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                        )
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(info.profile?.displayName ?? info.profile?.name ?? "Anonymous")
                        .font(.footnote.weight(.semibold))
                    
                    Spacer()
                    
                    if info.zapCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(info.zapCount)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(info.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let note = info.note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            // Zap button
            Button(action: {
                HapticManager.shared.impact(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showZapAnimation = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showZapAnimation = false
                }
                // TODO: Implement zap functionality
            }) {
                Image(systemName: showZapAnimation ? "bolt.circle.fill" : "bolt.circle")
                    .font(.body)
                    .foregroundColor(.orange)
                    .scaleEffect(showZapAnimation ? 1.2 : 1.0)
                    .rotationEffect(.degrees(showZapAnimation ? 360 : 0))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.05))
        )
    }
}