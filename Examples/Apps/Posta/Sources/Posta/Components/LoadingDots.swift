import SwiftUI

struct LoadingDots: View {
    let dotSize: CGFloat
    let color: Color
    @State private var animatingDots = [false, false, false]
    
    var body: some View {
        HStack(spacing: dotSize / 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animatingDots[index] ? 1.3 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animatingDots[index]
                    )
            }
        }
        .onAppear {
            for i in 0..<3 {
                animatingDots[i] = true
            }
        }
    }
}