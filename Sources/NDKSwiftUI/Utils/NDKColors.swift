import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - NDK Color Constants

/// Centralized color definitions for NDKSwiftUI components
extension Color {

    /// Background colors for different component contexts
    public static var ndkPrimaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #else
        return Color(red: 1.0, green: 1.0, blue: 1.0)
        #endif
    }

    public static var ndkSecondaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color.gray.opacity(OpacityConstants.light)
        #endif
    }

    public static var ndkTertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #else
        return Color.gray.opacity(OpacityConstants.ultraLight)
        #endif
    }

    public static var ndkGray5: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #else
        return Color.gray.opacity(OpacityConstants.medium)
        #endif
    }

    public static var ndkSeparator: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #else
        return Color.gray.opacity(OpacityConstants.semiOpaque)
        #endif
    }

    /// Accent color for interactive elements and highlights
    public static var ndkAccent: Color {
        Color.accentColor
    }
    
    /// Border color for UI elements
    public static var ndkBorder: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator).opacity(0.3)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
}