import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Opacity Constants

/// Common opacity values used throughout NDKSwiftUI components
public enum OpacityConstants {
    /// Ultra light opacity (5%)
    public static let ultraLight = 0.05
    
    /// Light opacity (10%)
    public static let light = 0.1
    
    /// Medium opacity (20%)
    public static let medium = 0.2
    
    /// Semi-opaque (30%)
    public static let semiOpaque = 0.3
    
    /// Half opacity (50%)
    public static let half = 0.5
    
    /// Strong opacity (60%)
    public static let strong = 0.6
    
    /// Heavy opacity (70%)
    public static let heavy = 0.7
}

// MARK: - NDK Color Constants

/// Centralized color definitions for NDKSwiftUI components
extension Color {
    
    /// Background colors for different component contexts
    static var ndkPrimaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #else
        return Color(red: 1.0, green: 1.0, blue: 1.0)
        #endif
    }
    
    static var ndkSecondaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color.gray.opacity(OpacityConstants.light)
        #endif
    }
    
    static var ndkTertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #else
        return Color.gray.opacity(OpacityConstants.ultraLight)
        #endif
    }
    
    static var ndkGray5: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #else
        return Color.gray.opacity(OpacityConstants.medium)
        #endif
    }
    
    static var ndkSeparator: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #else
        return Color.gray.opacity(OpacityConstants.semiOpaque)
        #endif
    }
}