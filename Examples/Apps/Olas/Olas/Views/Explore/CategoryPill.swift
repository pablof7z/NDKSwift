import SwiftUI

struct CategoryPill: View {
    let category: ExploreView.ExploreCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OlasDesign.Spacing.xs) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                
                Text(category.rawValue)
                    .font(OlasDesign.Typography.caption)
            }
            .foregroundColor(isSelected ? .white : OlasDesign.Colors.text)
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [OlasDesign.Colors.primary, OlasDesign.Colors.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        OlasDesign.Colors.surface
                    }
                }
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.clear : OlasDesign.Colors.border, lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
}