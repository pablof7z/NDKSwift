import SwiftUI

// Custom envelope shape for Posta logo
struct EnvelopeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        // Envelope body
        path.move(to: CGPoint(x: 0, y: height * 0.3))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width, y: height * 0.3))
        
        // Envelope flap
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.6))
        path.addLine(to: CGPoint(x: 0, y: height * 0.3))
        
        // Letter lines inside
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.45))
        path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.45))
        
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.6))
        path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.6))
        
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.75))
        path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.75))
        
        return path
    }
}

struct PostaLogoView: View {
    let size: CGFloat
    let color: Color
    @State private var letterOffset: CGFloat = 0
    @State private var letterRotation: Double = 0
    @State private var envelopeScale: CGFloat = 1
    
    init(size: CGFloat = 100, color: Color = .white) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        ZStack {
            // Background circle with gradient
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.3),
                            color.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 10)
            
            // Main envelope container
            ZStack {
                // Envelope back
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(color)
                    .frame(width: size, height: size * 0.7)
                    .offset(y: size * 0.15)
                    .scaleEffect(envelopeScale)
                
                // Envelope flap
                TriangleShape()
                    .fill(color.opacity(0.9))
                    .frame(width: size, height: size * 0.5)
                    .offset(y: -size * 0.1)
                    .scaleEffect(envelopeScale)
                
                // Letter inside with lightning bolt
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.05)
                        .fill(Color.white)
                        .frame(width: size * 0.7, height: size * 0.5)
                        .shadow(color: color.opacity(0.3), radius: 5, x: 0, y: 2)
                    
                    // Lightning bolt on letter
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.25, weight: .bold))
                        .foregroundColor(color)
                        .rotationEffect(.degrees(letterRotation))
                }
                .offset(y: letterOffset)
                .animation(
                    .spring(response: 0.8, dampingFraction: 0.6)
                        .repeatForever(autoreverses: true),
                    value: letterOffset
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                letterOffset = -size * 0.1
                letterRotation = 5
                envelopeScale = 1.05
            }
        }
    }
}

// Triangle shape for envelope flap
struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Animated envelope opening effect
struct AnimatedEnvelopeView: View {
    let size: CGFloat
    let color: Color
    @State private var isOpen = false
    @State private var letterScale: CGFloat = 0
    @State private var flapRotation: Double = 0
    
    var body: some View {
        ZStack {
            // Envelope body
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color,
                            color.opacity(0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size * 0.7)
                .offset(y: size * 0.15)
            
            // Envelope flap
            TriangleShape()
                .fill(color.opacity(0.9))
                .frame(width: size, height: size * 0.5)
                .offset(y: -size * 0.1)
                .rotation3DEffect(
                    .degrees(flapRotation),
                    axis: (x: 1.0, y: 0.0, z: 0.0),
                    anchor: .bottom,
                    anchorZ: 0,
                    perspective: 1.0
                )
            
            // Letter with content
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(Color.white)
                    .frame(width: size * 0.7, height: size * 0.8)
                    .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
                
                VStack(spacing: size * 0.05) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundColor(color)
                    
                    Text("POSTA")
                        .font(.system(size: size * 0.12, weight: .black, design: .rounded))
                        .foregroundColor(color)
                }
            }
            .scaleEffect(letterScale)
            .offset(y: isOpen ? -size * 0.3 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.5)) {
                isOpen = true
                flapRotation = -120
                letterScale = 1
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        PostaLogoView(size: 120, color: .purple)
        AnimatedEnvelopeView(size: 120, color: .purple)
    }
    .padding()
    .background(Color.black)
}