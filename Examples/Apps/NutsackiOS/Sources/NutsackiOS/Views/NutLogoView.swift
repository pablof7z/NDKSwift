import SwiftUI

struct NutLogoView: View {
    let size: CGFloat
    let color: Color
    
    init(size: CGFloat = 100, color: Color = .white) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        GeometryReader { geometry in
            let scale = size / 24
            
            ZStack {
                // Main nut shape paths
                Path { path in
                    // Top stem
                    path.move(to: CGPoint(x: 12 * scale, y: 4 * scale))
                    path.addLine(to: CGPoint(x: 12 * scale, y: 2 * scale))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                
                Path { path in
                    // Bottom V-shape
                    path.move(to: CGPoint(x: 5 * scale, y: 10 * scale))
                    path.addLine(to: CGPoint(x: 5 * scale, y: 14 * scale))
                    path.addCurve(
                        to: CGPoint(x: 10.277 * scale, y: 20.787 * scale),
                        control1: CGPoint(x: 5 * scale, y: 17.866 * scale),
                        control2: CGPoint(x: 7.368 * scale, y: 20.366 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 11.379 * scale, y: 21.379 * scale),
                        control1: CGPoint(x: 10.689 * scale, y: 20.891 * scale),
                        control2: CGPoint(x: 11.079 * scale, y: 21.079 * scale)
                    )
                    path.addLine(to: CGPoint(x: 12 * scale, y: 22 * scale))
                    path.addLine(to: CGPoint(x: 12.621 * scale, y: 21.379 * scale))
                    path.addCurve(
                        to: CGPoint(x: 13.723 * scale, y: 20.787 * scale),
                        control1: CGPoint(x: 12.921 * scale, y: 21.079 * scale),
                        control2: CGPoint(x: 13.311 * scale, y: 20.891 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 19 * scale, y: 14 * scale),
                        control1: CGPoint(x: 16.632 * scale, y: 20.366 * scale),
                        control2: CGPoint(x: 19 * scale, y: 17.866 * scale)
                    )
                    path.addLine(to: CGPoint(x: 19 * scale, y: 10 * scale))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
                
                Path { path in
                    // Top crown shape
                    path.move(to: CGPoint(x: 12 * scale, y: 4 * scale))
                    path.addCurve(
                        to: CGPoint(x: 4 * scale, y: 8 * scale),
                        control1: CGPoint(x: 8 * scale, y: 4 * scale),
                        control2: CGPoint(x: 4.5 * scale, y: 6 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 2 * scale, y: 11 * scale),
                        control1: CGPoint(x: 3.757 * scale, y: 8.97 * scale),
                        control2: CGPoint(x: 3.081 * scale, y: 9.952 * scale)
                    )
                    
                    // Left curve
                    path.addCurve(
                        to: CGPoint(x: 5 * scale, y: 10 * scale),
                        control1: CGPoint(x: 3.31 * scale, y: 10.918 * scale),
                        control2: CGPoint(x: 3.972 * scale, y: 10.71 * scale)
                    )
                    
                    // First valley
                    path.addCurve(
                        to: CGPoint(x: 7 * scale, y: 12 * scale),
                        control1: CGPoint(x: 5.54 * scale, y: 10.92 * scale),
                        control2: CGPoint(x: 5.982 * scale, y: 11.356 * scale)
                    )
                    
                    // Second peak
                    path.addCurve(
                        to: CGPoint(x: 9.5 * scale, y: 10 * scale),
                        control1: CGPoint(x: 8.452 * scale, y: 11.353 * scale),
                        control2: CGPoint(x: 8.954 * scale, y: 10.902 * scale)
                    )
                    
                    // Center valley
                    path.addCurve(
                        to: CGPoint(x: 12 * scale, y: 12 * scale),
                        control1: CGPoint(x: 10.095 * scale, y: 10.995 * scale),
                        control2: CGPoint(x: 10.651 * scale, y: 11.427 * scale)
                    )
                    
                    // Third peak
                    path.addCurve(
                        to: CGPoint(x: 14.5 * scale, y: 10 * scale),
                        control1: CGPoint(x: 13.349 * scale, y: 11.427 * scale),
                        control2: CGPoint(x: 13.905 * scale, y: 10.995 * scale)
                    )
                    
                    // Fourth valley
                    path.addCurve(
                        to: CGPoint(x: 17 * scale, y: 12 * scale),
                        control1: CGPoint(x: 15.046 * scale, y: 10.902 * scale),
                        control2: CGPoint(x: 15.548 * scale, y: 11.353 * scale)
                    )
                    
                    // Right curve
                    path.addCurve(
                        to: CGPoint(x: 19 * scale, y: 10 * scale),
                        control1: CGPoint(x: 18.018 * scale, y: 11.356 * scale),
                        control2: CGPoint(x: 18.46 * scale, y: 10.92 * scale)
                    )
                    
                    path.addCurve(
                        to: CGPoint(x: 22 * scale, y: 11 * scale),
                        control1: CGPoint(x: 20.028 * scale, y: 10.71 * scale),
                        control2: CGPoint(x: 20.69 * scale, y: 10.918 * scale)
                    )
                    
                    // Close to starting point
                    path.addCurve(
                        to: CGPoint(x: 20 * scale, y: 8 * scale),
                        control1: CGPoint(x: 20.919 * scale, y: 9.952 * scale),
                        control2: CGPoint(x: 20.243 * scale, y: 8.97 * scale)
                    )
                    path.addCurve(
                        to: CGPoint(x: 12 * scale, y: 4 * scale),
                        control1: CGPoint(x: 19.5 * scale, y: 6 * scale),
                        control2: CGPoint(x: 16 * scale, y: 4 * scale)
                    )
                    path.closeSubpath()
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

struct NutLogoView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            NutLogoView(size: 100, color: .orange)
            NutLogoView(size: 50, color: .white)
                .background(Color.black)
            NutLogoView(size: 200, color: .purple)
        }
    }
}