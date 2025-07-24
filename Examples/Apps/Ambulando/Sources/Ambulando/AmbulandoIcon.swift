import SwiftUI

struct AmbulandoIcon: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.6, green: 0.1, blue: 0.6),
                    Color(red: 0.5, green: 0.05, blue: 0.5),
                    Color(red: 0.7, green: 0.15, blue: 0.7)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Walking path
            Path { path in
                let steps = 8
                var points: [CGPoint] = []
                
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let x = size * 0.2 + t * size * 0.6
                    let y = size * 0.8 - t * size * 0.6 + size * 0.1 * sin(CGFloat(i) * .pi / 2)
                    points.append(CGPoint(x: x, y: y))
                }
                
                path.move(to: points[0])
                for i in 1..<points.count {
                    path.addLine(to: points[i])
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: size / 50)
            
            // Footsteps
            ForEach(0..<4) { i in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: size / 40, height: size / 40)
                    .position(
                        x: size * (0.3 + CGFloat(i) * 0.15),
                        y: size * (0.7 - CGFloat(i) * 0.15 + (i % 2 == 0 ? 0.05 : -0.05) * size)
                    )
            }
            
            // Letter "A"
            Text("A")
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color(red: 0.4, green: 0.05, blue: 0.4), radius: size / 100, x: size / 100, y: size / 100)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237))
    }
}

// Preview for development
struct AmbulandoIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AmbulandoIcon(size: 180)
            AmbulandoIcon(size: 120)
            AmbulandoIcon(size: 60)
        }
        .padding()
        .background(Color.gray)
    }
}