import SwiftUI

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color.white.opacity(0.3), location: 0.5),
                        .init(color: .clear, location: 0.7)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 400 - 200)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

// MARK: - Pulsing Effect

struct PulsingModifier: ViewModifier {
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double
    @State private var scale: CGFloat = 1
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    scale = maxScale
                }
            }
    }
}

extension View {
    func pulsing(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: Double = 2) -> some View {
        self.modifier(PulsingModifier(minScale: minScale, maxScale: maxScale, duration: duration))
    }
}