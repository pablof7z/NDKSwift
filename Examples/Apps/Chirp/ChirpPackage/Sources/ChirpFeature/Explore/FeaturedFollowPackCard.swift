import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Premium card design for featured follow packs in the horizontal scroll
struct FeaturedFollowPackCard: View {
    let ndk: NDK
    let pack: FollowPack

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background - image or gradient fallback
            background

            // Gradient overlay for text readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Floating avatars in top-right
            avatarStack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)

            // Content at bottom
            content
        }
        .frame(width: 280, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            profile = ndk.profile(for: pack.creatorPubkey)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let imageURL = pack.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    gradientBackground
                @unknown default:
                    gradientBackground
                }
            }
        } else {
            gradientBackground
        }
    }

    private var gradientBackground: some View {
        GeometryReader { _ in
            ZStack {
                // Base gradient from pack colors
                LinearGradient(
                    colors: baseGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Accent glow 1
                Circle()
                    .fill(accentColor1.opacity(0.4))
                    .blur(radius: 40)
                    .frame(width: 150, height: 150)
                    .offset(x: -60, y: 60)

                // Accent glow 2
                Circle()
                    .fill(accentColor2.opacity(0.3))
                    .blur(radius: 50)
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -40)
            }
        }
    }

    private var baseGradientColors: [Color] {
        let hash = pack.name.hashValue
        let hue1 = Double(abs(hash) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.2, brightness: 0.15),
            Color(hue: hue1, saturation: 0.3, brightness: 0.2)
        ]
    }

    private var accentColor1: Color {
        let hash = pack.name.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }

    private var accentColor2: Color {
        let hash = pack.name.hashValue
        let hue = Double(abs(hash >> 8) % 360) / 360.0
        return Color(hue: hue, saturation: 0.8, brightness: 0.7)
    }

    // MARK: - Avatar Stack

    private var avatarStack: some View {
        HStack(spacing: -12) {
            ForEach(Array(pack.pubkeys.prefix(3).enumerated()), id: \.element) { _, pubkey in
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 36)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }

            if pack.memberCount > 3 {
                Text("+\(pack.memberCount - 3)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 3)
                    }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(pack.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .lineLimit(1)

            // Meta info - just creator
            HStack(spacing: 4) {
                Text("by")
                    .foregroundStyle(.white.opacity(0.7))
                Text(profile?.displayName ?? "...")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 14))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}
