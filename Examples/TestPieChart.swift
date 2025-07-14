import SwiftUI

// Simplified test view to verify the pie chart rendering
struct TestPieChartView: View {
    @State private var mintBalances = [
        (mint: "https://testnut.cashu.space", balance: Int64(5000), percentage: 50.0),
        (mint: "https://mint.minibits.cash", balance: Int64(3000), percentage: 30.0),
        (mint: "https://legend.lnbits.com", balance: Int64(2000), percentage: 20.0)
    ]
    
    private let chartSize: CGFloat = 240
    private let innerRadius: CGFloat = 60
    
    private let mintColors: [Color] = [
        Color(red: 0.98, green: 0.54, blue: 0.13), // Orange
        Color(red: 0.13, green: 0.59, blue: 0.95), // Blue
        Color(red: 0.96, green: 0.26, blue: 0.21), // Red
    ]
    
    var body: some View {
        VStack {
            Text("Mint Allocation Test")
                .font(.title)
                .padding()
            
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: chartSize, height: chartSize)
                
                // Pie slices
                ForEach(Array(mintBalances.enumerated()), id: \.element.mint) { index, item in
                    SimplePieSlice(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        innerRadius: innerRadius,
                        outerRadius: chartSize / 2,
                        color: mintColors[index % mintColors.count]
                    )
                }
                
                // Center hole with total
                VStack(spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("10,000")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("sats")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: chartSize, height: chartSize)
            
            // Legend
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(mintBalances.enumerated()), id: \.element.mint) { index, item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(mintColors[index % mintColors.count])
                            .frame(width: 16, height: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatMintName(item.mint))
                                .font(.caption)
                            
                            Text("\(item.balance) sats (\(Int(item.percentage))%)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding()
        }
        .padding()
    }
    
    private func startAngle(for index: Int) -> Angle {
        guard index > 0 else { return .degrees(-90) }
        
        let previousAngles = mintBalances[0..<index].reduce(0) { sum, item in
            sum + (item.percentage / 100.0 * 360.0)
        }
        
        return .degrees(previousAngles - 90)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let cumulativeAngle = mintBalances[0...index].reduce(0) { sum, item in
            sum + (item.percentage / 100.0 * 360.0)
        }
        
        return .degrees(cumulativeAngle - 90)
    }
    
    private func formatMintName(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

struct SimplePieSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    
    var body: some View {
        SimplePieSliceShape(
            startAngle: startAngle,
            endAngle: endAngle,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )
        .fill(color)
    }
}

struct SimplePieSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        
        // Line to inner arc
        let innerEndPoint = CGPoint(
            x: center.x + innerRadius * cos(endAngle.radians),
            y: center.y + innerRadius * sin(endAngle.radians)
        )
        path.addLine(to: innerEndPoint)
        
        // Inner arc (reversed)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        
        // Close the path
        path.closeSubpath()
        
        return path
    }
}

// App entry point
@main
struct TestPieChartApp: App {
    var body: some Scene {
        WindowGroup {
            TestPieChartView()
        }
    }
}