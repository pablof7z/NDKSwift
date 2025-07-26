import SwiftUI

// MARK: - Message Card Component
struct MessageCard: View {
    let isPressed: Bool
    let hasUnread: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(hasUnread ? 0.3 : 0.1),
                                Color.purple.opacity(hasUnread ? 0.2 : 0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.purple.opacity(isPressed ? 0.15 : (hasUnread ? 0.1 : 0.05)),
                radius: isPressed ? 4 : 8,
                x: 0,
                y: isPressed ? 2 : 4
            )
    }
}

// MARK: - Floating Action Button
struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple,
                                Color.purple.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(
                        color: Color.purple.opacity(0.3),
                        radius: isPressed ? 4 : 12,
                        x: 0,
                        y: isPressed ? 2 : 6
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = pressing
                }
            },
            perform: { }
        )
    }
}

// MARK: - Enhanced Avatar View
struct EnhancedAvatarView: View {
    let url: URL?
    let size: CGFloat
    let fallbackText: String
    let showOnlineIndicator: Bool
    
    @State private var imageLoadFailed = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = url, !imageLoadFailed {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure(_):
                        fallbackView
                            .onAppear { imageLoadFailed = true }
                    case .empty:
                        shimmeringPlaceholder
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
            
            if showOnlineIndicator {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
            }
        }
    }
    
    private var fallbackView: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.3),
                        Color.purple.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(fallbackText)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(.purple)
            )
    }
    
    private var shimmeringPlaceholder: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .postaShimmer()
    }
}

// MARK: - Message Status Indicator
struct MessageStatusIndicator: View {
    enum Status {
        case sent, delivered, read, failed
    }
    
    let status: Status
    
    var body: some View {
        HStack(spacing: 2) {
            switch status {
            case .sent:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            case .delivered:
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            case .read:
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.purple)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Animated Header Background
struct AnimatedHeaderBackground: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            let gradient = Gradient(colors: [
                Color.purple.opacity(0.1),
                Color.purple.opacity(0.05),
                Color.clear
            ])
            
            // Draw animated gradient circles
            for i in 0..<3 {
                let offset = Double(i) * 120
                let x = size.width * 0.5 + Foundation.cos(phase + offset) * 30
                let y = size.height * 0.5 + Foundation.sin(phase + offset) * 20
                
                let circle = Circle()
                    .path(in: CGRect(
                        x: x - 60,
                        y: y - 60,
                        width: 120,
                        height: 120
                    ))
                
                context.fill(
                    circle,
                    with: .radialGradient(
                        gradient,
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: 60
                    )
                )
            }
        }
        .blur(radius: 20)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}