import SwiftUI

// MARK: - Chirp Design System
// Modern design system with iOS 26 Liquid Glass-ready components

// MARK: - Glass Effect Wrapper

/// A view modifier that applies a glass-like effect compatible with current iOS
/// and ready for Liquid Glass adoption when iOS 26 becomes available.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .padding(padding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                }
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Gradient Backgrounds

struct ChirpGradients {
    static let primary = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = LinearGradient(
        colors: [Color.orange, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtle = LinearGradient(
        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let background = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.05, blue: 0.15),
            Color(red: 0.1, green: 0.05, blue: 0.2)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Animated Background

struct AnimatedMeshBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Create multiple gradient blobs
                for i in 0..<3 {
                    let offset = Double(i) * 2.0
                    let x = sin(time * 0.3 + offset) * size.width * 0.3 + size.width * 0.5
                    let y = cos(time * 0.2 + offset) * size.height * 0.3 + size.height * 0.5
                    let radius = size.width * 0.4 + sin(time * 0.5 + offset) * 50

                    let colors: [Color] = [
                        [.blue, .purple, .cyan][i % 3],
                        .clear
                    ]

                    let gradient = Gradient(colors: colors)

                    context.fill(
                        Circle().path(in: CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: x, y: y),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .opacity(0.5)
        .blur(radius: 60)
        .ignoresSafeArea()
        .background(Color(red: 0.02, green: 0.02, blue: 0.08))
    }
}

// MARK: - Glass Button Styles

struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isProminent ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ChirpGradients.primary)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 60
    var color: Color = .blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5 - geo.size.width * 0.25)
                    .mask(content)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Content Card

struct ContentCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())

            Spacer()

            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Avatar with Status

struct AvatarWithStatus: View {
    let imageURL: URL?
    let size: CGFloat
    var isOnline: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                case .empty:
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    Circle()
                        .fill(.ultraThinMaterial)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2)
            }

            if isOnline {
                Circle()
                    .fill(.green)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay {
                        Circle()
                            .stroke(.white, lineWidth: 2)
                    }
                    .offset(x: 2, y: 2)
            }
        }
    }
}

// MARK: - Loading Placeholder

struct LoadingPlaceholder: View {
    var height: CGFloat = 100

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .frame(height: height)
            .shimmer()
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Get Started"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action {
                Button(actionLabel, action: action)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: 200)
                    .frame(height: 50)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(32)
    }
}

// MARK: - Pill Tag

struct PillTag: View {
    let text: String
    var color: Color = .blue

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(color.opacity(0.15))
            }
    }
}
