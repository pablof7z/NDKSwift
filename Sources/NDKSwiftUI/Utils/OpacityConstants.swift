import SwiftUI

/// Constants for UI opacity values used across NDKSwiftUI components
public enum OpacityConstants {
    /// Ultra light opacity (5%) - for very subtle backgrounds
    public static let ultraLight = 0.05

    /// Used for disabled or tertiary content (8%)
    public static let tertiary = 0.08

    /// Light opacity (10%) - for subtle background highlights (e.g., active states)
    public static let light = 0.1

    /// Subtle background highlights (10%) - alias for light
    public static let subtle = 0.1

    /// Medium opacity (20%) - for more visible overlays
    public static let medium = 0.2

    /// Used for borders and separators (30%)
    public static let border = 0.3

    /// Semi-opaque (30%) - alias for border
    public static let semiOpaque = 0.3

    /// Half opacity (50%) - for prominent overlays
    public static let half = 0.5

    /// Used for dimmed overlays (60%)
    public static let overlay = 0.6

    /// Strong opacity (60%) - alias for overlay
    public static let strong = 0.6

    /// Used for secondary content and labels (70%)
    public static let secondary = 0.7

    /// Heavy opacity (70%) - alias for secondary
    public static let heavy = 0.7
}