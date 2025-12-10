import SwiftUI

struct OlasLogo: View {
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let baseRadius = min(canvasSize.width, canvasSize.height) * 0.35
            let phi: CGFloat = 1.618

            var path = Path()

            // Golden spiral using quarter arcs
            var r = baseRadius
            var cx: CGFloat = 0
            var cy: CGFloat = 0

            // Offset center slightly for better visual balance
            let offsetX = center.x * 0.95
            let offsetY = center.y * 1.05

            // Start point
            path.move(to: CGPoint(x: offsetX + cx, y: offsetY + cy - r))

            // Quarter arc 1: top going right
            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )

            // Update for next arc
            var prevR = r
            r = r / phi
            cx = prevR
            cy = 0

            // Quarter arc 2: right going down
            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )

            // Update for next arc
            prevR = r
            r = r / phi
            cx = cx - prevR
            cy = prevR

            // Quarter arc 3: bottom going left
            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )

            // Update for next arc
            prevR = r
            r = r / phi
            cy = cy - prevR

            // Quarter arc 4: left going up
            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )

            // Update for next arc
            prevR = r
            r = r / phi
            cx = cx + prevR

            // Quarter arc 5
            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )

            // Update for next arc
            prevR = r
            r = r / phi
            cy = cy + prevR

            // Quarter arc 6
            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )

            // Quarter arc 7
            prevR = r
            r = r / phi
            cx = cx - prevR

            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )

            // Quarter arc 8
            prevR = r
            r = r / phi
            cy = cy - prevR

            path.addArc(
                center: CGPoint(x: offsetX + cx, y: offsetY + cy),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )

            // Draw with gradient stroke
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [OlasTheme.Colors.gradientStart, OlasTheme.Colors.gradientEnd]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                ),
                style: StrokeStyle(lineWidth: canvasSize.width * 0.035, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        OlasLogo(size: 120)
        OlasLogo(size: 80)
        OlasLogo(size: 40)
    }
    .padding()
}
