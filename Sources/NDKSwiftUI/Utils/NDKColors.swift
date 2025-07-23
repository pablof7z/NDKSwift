import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

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
        return Color.gray.opacity(0.1)
        #endif
    }
    
    static var ndkTertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #else
        return Color.gray.opacity(0.05)
        #endif
    }
    
    static var ndkGray5: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
    
    static var ndkSeparator: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}