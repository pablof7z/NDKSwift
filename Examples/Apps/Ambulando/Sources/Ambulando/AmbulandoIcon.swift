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
            
            // Main footprint
            FootprintIconShape()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.65, height: size * 0.75)
                .rotationEffect(.degrees(-15))
                .offset(x: -size * 0.05, y: -size * 0.05)
            
            // Shadow footprint for depth
            FootprintIconShape()
                .fill(Color(red: 0.4, green: 0.05, blue: 0.4).opacity(0.3))
                .frame(width: size * 0.65, height: size * 0.75)
                .rotationEffect(.degrees(-15))
                .offset(x: -size * 0.03, y: -size * 0.03)
                .blur(radius: size * 0.02)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237))
    }
}

// Custom shape for a realistic footprint
struct FootprintIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Main foot shape (heel to ball)
        path.move(to: CGPoint(x: width * 0.5, y: height * 0.95))
        
        // Left side of heel
        path.addCurve(
            to: CGPoint(x: width * 0.3, y: height * 0.75),
            control1: CGPoint(x: width * 0.35, y: height * 0.95),
            control2: CGPoint(x: width * 0.3, y: height * 0.85)
        )
        
        // Left side arch
        path.addCurve(
            to: CGPoint(x: width * 0.35, y: height * 0.45),
            control1: CGPoint(x: width * 0.3, y: height * 0.65),
            control2: CGPoint(x: width * 0.32, y: height * 0.55)
        )
        
        // Left side to ball of foot
        path.addCurve(
            to: CGPoint(x: width * 0.45, y: height * 0.3),
            control1: CGPoint(x: width * 0.38, y: height * 0.35),
            control2: CGPoint(x: width * 0.4, y: height * 0.3)
        )
        
        // Right side to ball of foot
        path.addCurve(
            to: CGPoint(x: width * 0.65, y: height * 0.45),
            control1: CGPoint(x: width * 0.55, y: height * 0.3),
            control2: CGPoint(x: width * 0.62, y: height * 0.35)
        )
        
        // Right side arch
        path.addCurve(
            to: CGPoint(x: width * 0.7, y: height * 0.75),
            control1: CGPoint(x: width * 0.68, y: height * 0.55),
            control2: CGPoint(x: width * 0.7, y: height * 0.65)
        )
        
        // Right side of heel
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: height * 0.95),
            control1: CGPoint(x: width * 0.7, y: height * 0.85),
            control2: CGPoint(x: width * 0.65, y: height * 0.95)
        )
        
        path.closeSubpath()
        
        // Big toe
        path.addEllipse(in: CGRect(
            x: width * 0.4,
            y: height * 0.08,
            width: width * 0.2,
            height: height * 0.15
        ))
        
        // Second toe
        path.addEllipse(in: CGRect(
            x: width * 0.25,
            y: height * 0.12,
            width: width * 0.15,
            height: height * 0.12
        ))
        
        // Middle toe
        path.addEllipse(in: CGRect(
            x: width * 0.15,
            y: height * 0.18,
            width: width * 0.12,
            height: height * 0.1
        ))
        
        // Fourth toe
        path.addEllipse(in: CGRect(
            x: width * 0.12,
            y: height * 0.25,
            width: width * 0.1,
            height: height * 0.08
        ))
        
        // Little toe
        path.addEllipse(in: CGRect(
            x: width * 0.15,
            y: height * 0.31,
            width: width * 0.08,
            height: height * 0.06
        ))
        
        return path
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