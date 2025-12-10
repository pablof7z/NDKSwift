import SwiftUI
import NDKSwiftCore

// MARK: - NDKEventViewStyles

/// Centralized styling system for NDKUIEventView and its sub-components.
/// Eliminates code duplication and ensures consistent styling across all event view types.
public struct NDKEventViewStyles {
    
    // MARK: - Spacing System
    
    /// Vertical spacing between components based on event style
    public static func verticalSpacing(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .full: return 12
        case .feed: return 8
        case .compact: return 6
        case .thread: return 10
        case .embedded: return 6
        }
    }
    
    /// Horizontal spacing between components based on event style
    public static func horizontalSpacing(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .full: return 16
        case .feed: return 12
        case .compact: return 8
        case .thread: return 12
        case .embedded: return 8
        }
    }
    
    // MARK: - Font System
    
    /// Content font based on event style
    public static func contentFont(for style: NDKUIEventView.EventStyle) -> Font {
        switch style {
        case .full: return .body
        case .feed: return .body
        case .compact: return .callout
        case .thread: return .body
        case .embedded: return .callout
        }
    }
    
    /// Title/headline font based on event style
    public static func titleFont(for style: NDKUIEventView.EventStyle) -> Font {
        switch style {
        case .full: return .title2
        case .feed: return .headline
        case .compact: return .subheadline
        case .thread: return .headline
        case .embedded: return .subheadline
        }
    }
    
    /// Caption/metadata font based on event style
    public static func captionFont(for style: NDKUIEventView.EventStyle) -> Font {
        switch style {
        case .full: return .caption
        case .feed: return .caption
        case .compact: return .caption2
        case .thread: return .caption
        case .embedded: return .caption2
        }
    }
    
    // MARK: - Line Limits
    
    /// Content line limit based on event style
    public static func contentLineLimit(for style: NDKUIEventView.EventStyle) -> Int? {
        switch style {
        case .full: return nil
        case .feed: return 6
        case .compact: return 3
        case .thread: return nil
        case .embedded: return 3
        }
    }
    
    /// Title line limit based on event style
    public static func titleLineLimit(for style: NDKUIEventView.EventStyle) -> Int? {
        switch style {
        case .full: return nil
        case .feed: return 2
        case .compact: return 2
        case .thread: return 2
        case .embedded: return 1
        }
    }
    
    // MARK: - Container Styling
    
    /// Container padding based on event style
    public static func containerPadding(for style: NDKUIEventView.EventStyle) -> EdgeInsets {
        switch style {
        case .full: return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .feed: return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .compact: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        case .thread: return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .embedded: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        }
    }
    
    /// Background color based on event style
    public static func backgroundColor(for style: NDKUIEventView.EventStyle) -> Color {
        switch style {
        case .embedded, .compact: return Color.ndkSecondaryBackground
        default: return Color.clear
        }
    }
    
    /// Corner radius based on event style
    public static func cornerRadius(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .embedded, .compact: return 12
        case .full: return 8
        default: return 0
        }
    }
    
    // MARK: - Author Header Styles
    
    /// Author header style mapping
    public static func authorHeaderStyle(for style: NDKUIEventView.EventStyle) -> NDKUIEventAuthorHeader.Style {
        switch style {
        case .full: return .detailed
        case .feed: return .standard
        case .compact: return .minimal
        case .thread: return .standard
        case .embedded: return .minimal
        }
    }
    
    // MARK: - Interaction Bar Styles
    
    /// Interaction bar style mapping
    public static func interactionBarStyle(for style: NDKUIEventView.EventStyle) -> NDKEventInteractionBar.Style {
        switch style {
        case .full: return .detailed
        case .feed: return .standard
        case .compact: return .minimal
        case .thread: return .standard
        case .embedded: return .minimal
        }
    }
    
    // MARK: - Image Styling
    
    /// Image height for single images based on event style
    public static func imageHeight(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .compact: return UIConstants.EventImageHeight.compact
        case .embedded: return UIConstants.EventImageHeight.embedded
        default: return UIConstants.EventImageHeight.default
        }
    }
    
    /// Grid image height for multiple images based on event style
    public static func gridImageHeight(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .compact: return 80
        case .embedded: return 100
        default: return 120
        }
    }
    
    // MARK: - Card Styling
    
    /// Card padding for specialized content (articles, tokens, etc.)
    public static func cardPadding(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .full: return 16
        case .feed: return 12
        case .compact: return 8
        case .thread: return 12
        case .embedded: return 8
        }
    }
    
    /// Card corner radius for specialized content
    public static func cardCornerRadius(for style: NDKUIEventView.EventStyle) -> CGFloat {
        switch style {
        case .full: return 16
        case .feed: return 12
        case .compact: return 8
        case .thread: return 12
        case .embedded: return 8
        }
    }
}

// MARK: - ViewModifier Extensions

/// View modifier for applying consistent event view styling
public struct NDKEventViewStyle: ViewModifier {
    let style: NDKUIEventView.EventStyle
    
    public func body(content: Content) -> some View {
        content
            .padding(NDKEventViewStyles.containerPadding(for: style))
            .background(NDKEventViewStyles.backgroundColor(for: style))
            .cornerRadius(NDKEventViewStyles.cornerRadius(for: style))
    }
}

/// View modifier for applying consistent card styling
public struct NDKEventCardStyle: ViewModifier {
    let style: NDKUIEventView.EventStyle
    let backgroundColor: Color
    
    public init(style: NDKUIEventView.EventStyle, backgroundColor: Color = Color.ndkSecondaryBackground) {
        self.style = style
        self.backgroundColor = backgroundColor
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(NDKEventViewStyles.cardPadding(for: style))
            .background(backgroundColor)
            .cornerRadius(NDKEventViewStyles.cardCornerRadius(for: style))
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard event view styling
    public func ndkEventViewStyle(_ style: NDKUIEventView.EventStyle) -> some View {
        self.modifier(NDKEventViewStyle(style: style))
    }
    
    /// Apply card styling for specialized content
    public func ndkEventCardStyle(_ style: NDKUIEventView.EventStyle, backgroundColor: Color = Color.ndkSecondaryBackground) -> some View {
        self.modifier(NDKEventCardStyle(style: style, backgroundColor: backgroundColor))
    }
}