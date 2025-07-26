import SwiftUI

struct OlasButton: View {
    let title: String
    let action: () -> Void
    var style: OlasButtonStyle = .primary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    
    enum OlasButtonStyle {
        case primary
        case secondary
        case tertiary
        
        var background: some View {
            Group {
                switch self {
                case .primary:
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                case .secondary:
                    Color.clear
                        .overlay(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                .stroke(OlasDesign.Colors.divider, lineWidth: 1)
                        )
                case .tertiary:
                    Color.clear
                }
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary:
                return .white
            case .secondary, .tertiary:
                return OlasDesign.Colors.text
            }
        }
    }
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            if !isLoading && !isDisabled {
                OlasDesign.Haptic.selection()
                action()
            }
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(Color.clear)
                    .background(style.background)
                    .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
                
                // Content
                HStack(spacing: OlasDesign.Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                            .scaleEffect(0.8)
                    } else {
                        Text(title)
                            .font(OlasDesign.Typography.bodyBold)
                            .foregroundColor(style.foregroundColor)
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.lg)
                .padding(.vertical, OlasDesign.Spacing.md)
            }
            .opacity(isDisabled ? 0.5 : 1)
            .scaleEffect(isPressed ? 0.95 : 1)
        }
        .disabled(isLoading || isDisabled)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        } perform: {}
    }
}

// MARK: - Convenience Modifiers
extension OlasButton {
    func loading(_ isLoading: Bool) -> OlasButton {
        var button = self
        button.isLoading = isLoading
        return button
    }
    
    func disabled(_ isDisabled: Bool) -> OlasButton {
        var button = self
        button.isDisabled = isDisabled
        return button
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        OlasButton(title: "Follow", action: {})
        
        OlasButton(title: "Following", action: {}, style: .secondary)
        
        OlasButton(title: "Loading", action: {})
            .loading(true)
        
        OlasButton(title: "Disabled", action: {})
            .disabled(true)
        
        OlasButton(title: "Tertiary", action: {}, style: .tertiary)
    }
    .padding()
    .background(OlasDesign.Colors.background)
}