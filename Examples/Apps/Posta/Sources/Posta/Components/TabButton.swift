import SwiftUI

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .purple : .secondary)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .purple : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple.opacity(0.1))
                    }
                }
            )
            .overlay(
                GeometryReader { geometry in
                    if isSelected {
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.purple)
                                .frame(width: geometry.size.width * 0.6, height: 2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}