import SwiftUI

struct TrendingHashtagPill: View {
    let hashtag: ExploreView.TrendingHashtag
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("#\(hashtag.tag)")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.primary)
                    
                    // Trending indicator
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(OlasDesign.Colors.success)
                }
                
                HStack(spacing: 8) {
                    Text("\(hashtag.count)")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Text("·")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                    
                    Text("\(Int(hashtag.velocity))/hr")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(OlasDesign.Colors.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OlasDesign.Colors.border, lineWidth: 1)
            )
        }
    }
}