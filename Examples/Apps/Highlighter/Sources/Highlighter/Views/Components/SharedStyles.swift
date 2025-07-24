import SwiftUI

// MARK: - Specialized Components for Highlighter
// This file contains Highlighter-specific components that extend the base DesignSystem

// All typography and button styles have been consolidated into DesignSystem.swift
// This file now focuses on Highlighter-specific utilities and extensions

extension Font {
    // Convenience accessor for typography from DesignSystem
    static let highlighterQuote = DesignSystem.Typography.highlighterQuote
    
    // Dynamic quote sizing - moved from old SharedStyles
    static func dynamicQuote(for length: Int) -> Font {
        return DesignSystem.Typography.dynamicQuote(for: length)
    }
}

// MARK: - Specialized View Extensions for Content Rendering

extension View {
    /// Lazy rendering modifier for better scroll performance - consolidated into DesignSystem
    func lazyRender(threshold: CGFloat = 100) -> some View {
        self.modifier(LazyRenderModifier(threshold: threshold))
    }
    
    /// Enhanced zap button styling - consolidated into DesignSystem  
    func enhancedZapButton() -> some View {
        self.buttonStyle(DesignSystem.EnhancedZapButtonStyle())
    }
}

// MARK: - Specialized Modifiers for Highlighter Content

/// Performance optimization for scroll views with many items
struct ContentOptimizationModifier: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0.3)
            .scaleEffect(isVisible ? 1 : 0.98)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}

extension View {
    func optimizeForScrolling(isVisible: Bool) -> some View {
        self.modifier(ContentOptimizationModifier(isVisible: isVisible))
    }
}