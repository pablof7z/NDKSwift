import SwiftUI

/// Configuration for markdown block-level styling
public struct MarkdownBlockConfig {
    // Spacing
    public var blockSpacing: CGFloat
    public var listItemSpacing: CGFloat
    public var listIndent: CGFloat

    // Headings
    public var headingColor: Color
    public var headingFonts: [Int: Font]

    // Code blocks
    public var codeBackgroundColor: Color
    public var codeFont: Font
    public var codeCornerRadius: CGFloat
    public var codePadding: CGFloat

    // Blockquotes
    public var blockquoteBorderColor: Color
    public var blockquoteTextColor: Color

    public init(
        blockSpacing: CGFloat = 12,
        listItemSpacing: CGFloat = 4,
        listIndent: CGFloat = 20,
        headingColor: Color = .primary,
        headingFonts: [Int: Font] = [
            1: .largeTitle.bold(),
            2: .title.bold(),
            3: .title2.bold(),
            4: .title3.bold(),
            5: .headline,
            6: .subheadline.bold()
        ],
        codeBackgroundColor: Color = Color.secondary.opacity(0.1),
        codeFont: Font = .system(.body, design: .monospaced),
        codeCornerRadius: CGFloat = 8,
        codePadding: CGFloat = 12,
        blockquoteBorderColor: Color = .accentColor,
        blockquoteTextColor: Color = .secondary
    ) {
        self.blockSpacing = blockSpacing
        self.listItemSpacing = listItemSpacing
        self.listIndent = listIndent
        self.headingColor = headingColor
        self.headingFonts = headingFonts
        self.codeBackgroundColor = codeBackgroundColor
        self.codeFont = codeFont
        self.codeCornerRadius = codeCornerRadius
        self.codePadding = codePadding
        self.blockquoteBorderColor = blockquoteBorderColor
        self.blockquoteTextColor = blockquoteTextColor
    }

    public func headingFont(for level: Int) -> Font {
        headingFonts[level] ?? .body
    }

    // MARK: - Presets

    public static let `default` = MarkdownBlockConfig()

    public static let minimal = MarkdownBlockConfig(
        blockSpacing: 8,
        codeBackgroundColor: .clear,
        codePadding: 0
    )

    public static let compact = MarkdownBlockConfig(
        blockSpacing: 6,
        listItemSpacing: 2
    )
}
