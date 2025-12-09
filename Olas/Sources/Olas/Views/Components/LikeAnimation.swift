import SwiftUI

struct LikeAnimation: View {
    @Binding var isAnimating: Bool

    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 80, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    animate()
                }
            }
    }

    private func animate() {
        // Initial burst
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)) {
            scale = 1.3
            opacity = 1
        }

        // Settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scale = 1.0
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
                scale = 1.2
            }
        }

        // Reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            scale = 0
            isAnimating = false
        }
    }
}

struct HeartButtonStyle: ButtonStyle {
    let isLiked: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct LikeButton: View {
    @Binding var isLiked: Bool
    let likeCount: Int
    let onLike: () -> Void

    @State private var animateHeart = false

    var body: some View {
        Button {
            triggerHaptic()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                isLiked.toggle()
                if isLiked {
                    animateHeart = true
                }
            }
            onLike()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isLiked ? OlasTheme.Colors.heartRed : .primary)
                    .scaleEffect(animateHeart ? 1.2 : 1.0)

                if likeCount > 0 {
                    Text("\(likeCount)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(HeartButtonStyle(isLiked: isLiked))
        .onChange(of: animateHeart) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        animateHeart = false
                    }
                }
            }
        }
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

struct CommentButton: View {
    let commentCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 20, weight: .medium))

                if commentCount > 0 {
                    Text("\(commentCount)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

struct ZapButton: View {
    let zapAmount: Int
    let action: () -> Void

    @State private var isAnimating = false

    var body: some View {
        Button {
            triggerHaptic()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAnimating = false
            }
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(OlasTheme.Colors.zapGold)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .rotationEffect(.degrees(isAnimating ? 10 : 0))

                if zapAmount > 0 {
                    Text(formatSats(zapAmount))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatSats(_ amount: Int) -> String {
        if amount >= 1000000 {
            return String(format: "%.1fM", Double(amount) / 1000000)
        } else if amount >= 1000 {
            return String(format: "%.1fK", Double(amount) / 1000)
        }
        return "\(amount)"
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

struct ShareButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane")
                .font(.system(size: 20, weight: .medium))
        }
        .foregroundStyle(.primary)
    }
}
