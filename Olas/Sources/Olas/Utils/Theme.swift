// Theme.swift
import SwiftUI

public enum OlasTheme {
    // MARK: - Colors
    public enum Colors {
        // Primary accent - neutral black/white (adapts to light/dark mode)
        public static let accent = Color.primary

        // Legacy aliases - now neutral
        public static let deepTeal = Color.primary
        public static let oceanBlue = Color.primary
        public static let seafoam = Color.secondary

        // Feedback colors
        public static let zapGold = Color(hex: "FFB800")
        public static let heartRed = Color(hex: "FF4757")
        public static let success = Color(hex: "2ED573")

        // Light mode
        public static let backgroundLight = Color(hex: "F8FFFE")
        public static let cardLight = Color.white.opacity(0.7)
        public static let textLight = Color(hex: "1A2B32")
        public static let secondaryLight = Color(hex: "6B8187")

        // Dark mode
        public static let backgroundDark = Color(hex: "0A1215")
        public static let cardDark = Color(hex: "142125").opacity(0.7)
        public static let textDark = Color(hex: "E8F4F5")
        public static let secondaryDark = Color(hex: "7B9BA1")
    }

    // MARK: - Glassmorphism
    public enum Glass {
        public static let cornerRadius: CGFloat = 20
        public static let shadowRadius: CGFloat = 20
        public static let shadowOpacity: Double = 0.1
    }

    // MARK: - Spacing
    public enum Spacing {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers
public struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(OlasTheme.Glass.cornerRadius)
            .shadow(
                color: .black.opacity(OlasTheme.Glass.shadowOpacity),
                radius: OlasTheme.Glass.shadowRadius,
                y: 10
            )
    }
}

extension View {
    public func glassBackground() -> some View {
        modifier(GlassBackground())
    }
}
