import SwiftUI
import NDKSwift

struct ExploreGridItem: View {
    let post: NDKEvent
    let profile: NDKUserProfile?
    let height: CGFloat
    
    @State private var imageUrls: [String] = []
    @State private var showingPost = false
    
    var body: some View {
        NavigationLink(destination: PostDetailView(event: post)) {
            ZStack(alignment: .bottomLeading) {
                // Image
                if let firstImageUrl = imageUrls.first,
                   let url = URL(string: firstImageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            shimmerPlaceholder
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: height)
                                .clipped()
                        case .failure:
                            imagePlaceholder
                        @unknown default:
                            shimmerPlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }
                
                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.6)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // Content overlay
                VStack(alignment: .leading, spacing: 4) {
                    // Profile info
                    HStack(spacing: OlasDesign.Spacing.xs) {
                        OlasAvatar(
                            url: profile?.picture,
                            size: 24,
                            pubkey: post.pubkey
                        )
                        
                        Text(profile?.displayName ?? profile?.name ?? "...")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    
                    // Preview text
                    if !post.content.isEmpty {
                        Text(cleanContent(post.content))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(OlasDesign.Spacing.sm)
            }
            .frame(height: height)
            .background(OlasDesign.Colors.surface)
            .cornerRadius(0)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            imageUrls = extractImageUrls(from: post.content)
        }
    }
    
    @ViewBuilder
    private var shimmerPlaceholder: some View {
        Rectangle()
            .fill(OlasDesign.Colors.surface)
            .overlay(
                ShimmerView()
            )
            .frame(height: height)
    }
    
    @ViewBuilder
    private var imagePlaceholder: some View {
        ZStack {
            OlasDesign.Colors.surface
            
            Image(systemName: "photo")
                .font(.system(size: 30))
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
        .frame(height: height)
    }
    
    private func cleanContent(_ content: String) -> String {
        // Remove image URLs and clean up the text
        var cleaned = content
        
        // Remove URLs
        let urlPattern = "https?://[^\\s]+"
        cleaned = cleaned.replacingOccurrences(
            of: urlPattern,
            with: "",
            options: .regularExpression
        )
        
        // Remove extra whitespace
        cleaned = cleaned
            .split(separator: " ")
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    private func extractImageUrls(from content: String) -> [String] {
        let pattern = "(https?://[^\\s]+\\.(jpg|jpeg|png|gif|webp)[^\\s]*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: content) else { return nil }
            return String(content[range])
        }
    }
}

// Simple shimmer effect
struct ShimmerView: View {
    @State private var offset: CGFloat = -1
    
    var body: some View {
        LinearGradient(
            colors: [
                OlasDesign.Colors.surface,
                OlasDesign.Colors.surface.opacity(0.7),
                OlasDesign.Colors.surface
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: offset * 200)
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                offset = 2
            }
        }
    }
}