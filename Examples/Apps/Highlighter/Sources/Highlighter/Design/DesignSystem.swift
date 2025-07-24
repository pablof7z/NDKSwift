import SwiftUI

// MARK: - Modern Design System
// A premium, sophisticated design language inspired by contemporary apps

struct DesignSystem {
    
    // MARK: - Colors
    enum Colors {
        // Primary - A sophisticated accent color (deep indigo)
        static let primary = Color(hex: "5856D6")
        static let primaryLight = Color(hex: "7C7AFF")
        static let primaryDark = Color(hex: "3634A3")
        
        // Semantic Colors
        static let text = Color.primary
        static let textSecondary = Color.primary.opacity(0.6)
        static let textTertiary = Color.primary.opacity(0.4)
        
        // Backgrounds - Clean, minimal
        static let background = Color(UIColor.systemBackground)
        static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
        static let surface = Color(UIColor.systemBackground)
        static let surfaceSecondary = Color(UIColor.secondarySystemBackground).opacity(0.5)
        
        // Functional
        static let success = Color(hex: "34C759")
        static let warning = Color(hex: "FF9500")
        static let error = Color(hex: "FF3B30")
        
        // Borders & Dividers
        static let divider = Color.primary.opacity(0.08)
        static let border = Color.primary.opacity(0.12)
        
        // Interactive States
        static let highlight = Color(hex: "FFD60A") // Clean yellow for highlights
        static let highlightSubtle = Color(hex: "FFD60A").opacity(0.1)
    }
    
    // MARK: - Typography
    enum Typography {
        // Display
        static let largeTitle = Font.system(size: 32, weight: .bold, design: .default)
        static let title = Font.system(size: 24, weight: .semibold, design: .default)
        static let title2 = Font.system(size: 20, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 18, weight: .medium, design: .default)
        
        // Body
        static let headline = Font.system(size: 16, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 15, weight: .medium, design: .default)
        static let callout = Font.system(size: 14, weight: .regular, design: .default)
        
        // Support
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let footnoteMedium = Font.system(size: 13, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)
        static let micro = Font.system(size: 11, weight: .regular, design: .default)
    }
    
    // MARK: - Spacing (Tighter, more modern)
    enum Spacing {
        static let nano: CGFloat = 2
        static let micro: CGFloat = 4
        static let mini: CGFloat = 6
        static let small: CGFloat = 8
        static let base: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let huge: CGFloat = 40
        
        // Specific use cases
        static let cardPadding: CGFloat = 16
        static let screenPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let itemSpacing: CGFloat = 12
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let micro: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 999
    }
    
    // MARK: - Shadows (Subtle and sophisticated)
    enum Shadow {
        static let subtle = (
            color: Color.black.opacity(0.04),
            radius: CGFloat(2),
            x: CGFloat(0),
            y: CGFloat(1)
        )
        
        static let small = (
            color: Color.black.opacity(0.06),
            radius: CGFloat(4),
            x: CGFloat(0),
            y: CGFloat(2)
        )
        
        static let medium = (
            color: Color.black.opacity(0.08),
            radius: CGFloat(8),
            x: CGFloat(0),
            y: CGFloat(4)
        )
        
        static let large = (
            color: Color.black.opacity(0.12),
            radius: CGFloat(16),
            x: CGFloat(0),
            y: CGFloat(8)
        )
        
        static let elevated = (
            color: Color.black.opacity(0.15),
            radius: CGFloat(24),
            x: CGFloat(0),
            y: CGFloat(12)
        )
    }
    
    // MARK: - Animation (Snappy and responsive)
    enum Animation {
        static let instant = SwiftUI.Animation.easeOut(duration: 0.15)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeOut(duration: 0.25)
        static let smooth = SwiftUI.Animation.easeOut(duration: 0.35)
        
        // Spring animations
        static let springSnappy = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let springSmooth = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let springBouncy = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6)
        
        // Interactive animations
        static let interactive = SwiftUI.Animation.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.25)
    }
    
    // MARK: - Layout
    enum Layout {
        static let maxContentWidth: CGFloat = 600
        static let compactBreakpoint: CGFloat = 400
        static let regularBreakpoint: CGFloat = 768
    }
}

// MARK: - Convenience extensions
extension Color {
    static let ds = DesignSystem.Colors.self
}

extension Font {
    static let ds = DesignSystem.Typography.self
}

extension CGFloat {
    static let ds = DesignSystem.Spacing.self
}

