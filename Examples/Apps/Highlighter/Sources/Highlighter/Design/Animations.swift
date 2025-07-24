import SwiftUI

struct SpringyScale: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isActive)
    }
}

struct SlideInFromBottom: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .offset(y: isVisible ? 0 : UIScreen.main.bounds.height)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isVisible)
    }
}


struct BounceEffect: ViewModifier {
    @State private var bounceScale: CGFloat = 1
    let trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(bounceScale)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                    bounceScale = 1.2
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.1)) {
                    bounceScale = 1.0
                }
            }
    }
}

struct TypewriterEffect: ViewModifier {
    let text: String
    let speed: Double
    @State private var displayedText = ""
    @State private var currentIndex = 0
    
    func body(content: Content) -> some View {
        Text(displayedText)
            .onAppear {
                animateText()
            }
            .onChange(of: text) { _, newValue in
                displayedText = ""
                currentIndex = 0
                animateText()
            }
    }
    
    private func animateText() {
        guard currentIndex < text.count else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + speed) {
            let index = text.index(text.startIndex, offsetBy: currentIndex)
            displayedText += String(text[index])
            currentIndex += 1
            animateText()
        }
    }
}

extension View {
    func springyScale(isActive: Bool) -> some View {
        modifier(SpringyScale(isActive: isActive))
    }
    
    func slideInFromBottom(isVisible: Bool) -> some View {
        modifier(SlideInFromBottom(isVisible: isVisible))
    }
    
    
    func bounceEffect(trigger: Bool) -> some View {
        modifier(BounceEffect(trigger: trigger))
    }
    
    func typewriter(_ text: String, speed: Double = 0.05) -> some View {
        modifier(TypewriterEffect(text: text, speed: speed))
    }
}

struct AnimatedCheckmark: View {
    let isChecked: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2)
                .foregroundColor(.gray.opacity(0.3))
                .frame(width: 24, height: 24)
            
            if isChecked {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .transition(.scale.combined(with: .opacity))
                
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isChecked)
    }
}

