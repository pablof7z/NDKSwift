import XCTest
@testable import NDKSwiftUI
@testable import NDKSwiftCore

final class MarkdownParserTests: XCTestCase {

    // MARK: - Heading Tests

    func testHeadingLevel1() {
        let content = "# Heading 1"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .heading(level, text) = blocks[0] else {
            XCTFail("Expected heading block")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "Heading 1")
    }

    func testHeadingLevel2Through6() {
        let testCases = [
            ("## Heading 2", 2, "Heading 2"),
            ("### Heading 3", 3, "Heading 3"),
            ("#### Heading 4", 4, "Heading 4"),
            ("##### Heading 5", 5, "Heading 5"),
            ("###### Heading 6", 6, "Heading 6")
        ]

        for (content, expectedLevel, expectedText) in testCases {
            let blocks = MarkdownParser.parse(content)
            XCTAssertEqual(blocks.count, 1)
            guard case let .heading(level, text) = blocks[0] else {
                XCTFail("Expected heading block for \(content)")
                continue
            }
            XCTAssertEqual(level, expectedLevel)
            XCTAssertEqual(text, expectedText)
        }
    }

    func testHeadingRequiresSpace() {
        let content = "#NoSpace"
        let blocks = MarkdownParser.parse(content)

        // Should be parsed as paragraph, not heading
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph = blocks[0] else {
            XCTFail("Expected paragraph block")
            return
        }
    }

    // MARK: - Paragraph Tests

    func testSimpleParagraph() {
        let content = "This is a simple paragraph."
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph block")
            return
        }
        XCTAssertEqual(inlines.count, 1)
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text inline")
            return
        }
        XCTAssertEqual(text, "This is a simple paragraph.")
    }

    func testMultiLineParagraph() {
        let content = """
        Line 1
        Line 2
        Line 3
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph block")
            return
        }
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text inline")
            return
        }
        // Lines should be joined with spaces
        XCTAssertTrue(text.contains("Line 1"))
        XCTAssertTrue(text.contains("Line 2"))
        XCTAssertTrue(text.contains("Line 3"))
    }

    // MARK: - Code Block Tests

    func testCodeBlockWithoutLanguage() {
        let content = """
        ```
        const x = 1
        const y = 2
        ```
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .codeBlock(language, code) = blocks[0] else {
            XCTFail("Expected code block")
            return
        }
        XCTAssertNil(language)
        XCTAssertEqual(code, "const x = 1\nconst y = 2")
    }

    func testCodeBlockWithLanguage() {
        let content = """
        ```swift
        func hello() {
            print("Hello")
        }
        ```
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .codeBlock(language, code) = blocks[0] else {
            XCTFail("Expected code block")
            return
        }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(code.contains("func hello()"))
    }

    func testUnclosedCodeBlock() {
        let content = """
        ```
        This code block is not closed
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .codeBlock(_, code) = blocks[0] else {
            XCTFail("Expected code block")
            return
        }
        XCTAssertEqual(code, "This code block is not closed")
    }

    // MARK: - Blockquote Tests

    func testSimpleBlockquote() {
        let content = "> This is a quote"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .blockquote(inlines) = blocks[0] else {
            XCTFail("Expected blockquote block")
            return
        }
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text inline")
            return
        }
        XCTAssertEqual(text, "This is a quote")
    }

    func testMultiLineBlockquote() {
        let content = """
        > Line 1
        > Line 2
        > Line 3
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .blockquote(inlines) = blocks[0] else {
            XCTFail("Expected blockquote block")
            return
        }
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text inline")
            return
        }
        XCTAssertTrue(text.contains("Line 1"))
        XCTAssertTrue(text.contains("Line 2"))
        XCTAssertTrue(text.contains("Line 3"))
    }

    // MARK: - List Tests

    func testUnorderedList() {
        let content = """
        - Item 1
        - Item 2
        - Item 3
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .list(items, ordered) = blocks[0] else {
            XCTFail("Expected list block")
            return
        }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.count, 3)
    }

    func testUnorderedListAlternativeMarkers() {
        let asteriskContent = """
        * Item 1
        * Item 2
        """
        let plusContent = """
        + Item 1
        + Item 2
        """

        for content in [asteriskContent, plusContent] {
            let blocks = MarkdownParser.parse(content)
            XCTAssertEqual(blocks.count, 1)
            guard case let .list(items, ordered) = blocks[0] else {
                XCTFail("Expected list block for \(content)")
                continue
            }
            XCTAssertFalse(ordered)
            XCTAssertEqual(items.count, 2)
        }
    }

    func testOrderedList() {
        let content = """
        1. First item
        2. Second item
        3. Third item
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .list(items, ordered) = blocks[0] else {
            XCTFail("Expected list block")
            return
        }
        XCTAssertTrue(ordered, "List should be marked as ordered")
        XCTAssertEqual(items.count, 3)

        // Verify content
        guard case let .text(firstText) = items[0].content[0] else {
            XCTFail("Expected text in first item")
            return
        }
        XCTAssertEqual(firstText, "First item")
    }

    // MARK: - Horizontal Rule Tests

    func testHorizontalRule() {
        let rules = ["---", "***", "___"]

        for rule in rules {
            let blocks = MarkdownParser.parse(rule)
            XCTAssertEqual(blocks.count, 1)
            guard case .horizontalRule = blocks[0] else {
                XCTFail("Expected horizontal rule for \(rule)")
                continue
            }
        }
    }

    // MARK: - Inline Formatting Tests

    func testBoldText() {
        let content = "This is **bold** text"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        // Should have: text, bold, text
        XCTAssertGreaterThanOrEqual(inlines.count, 3)

        // Find the bold element
        let boldElement = inlines.first { inline in
            if case .bold = inline { return true }
            return false
        }
        XCTAssertNotNil(boldElement)
    }

    func testItalicText() {
        let content = "This is *italic* text"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        let italicElement = inlines.first { inline in
            if case .italic = inline { return true }
            return false
        }
        XCTAssertNotNil(italicElement)
    }

    func testInlineCode() {
        let content = "This is `code` text"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        let codeElement = inlines.first { inline in
            if case let .code(text) = inline {
                return text == "code"
            }
            return false
        }
        XCTAssertNotNil(codeElement)
    }

    func testLink() {
        let content = "[Click here](https://example.com)"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        XCTAssertEqual(inlines.count, 1)
        guard case let .link(text, url) = inlines[0] else {
            XCTFail("Expected link")
            return
        }
        XCTAssertEqual(text, "Click here")
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testImage() {
        let content = "![Alt text](https://example.com/image.png)"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        XCTAssertEqual(inlines.count, 1)
        guard case let .image(alt, url) = inlines[0] else {
            XCTFail("Expected image")
            return
        }
        XCTAssertEqual(alt, "Alt text")
        XCTAssertEqual(url.absoluteString, "https://example.com/image.png")
    }

    // MARK: - Nostr Entity Tests

    func testHashtagParsing() {
        let content = "Check out #nostr and #bitcoin"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        let hashtags = inlines.compactMap { inline -> String? in
            if case let .hashtag(tag) = inline {
                return tag
            }
            return nil
        }

        XCTAssertEqual(hashtags.count, 2)
        XCTAssertTrue(hashtags.contains("nostr"))
        XCTAssertTrue(hashtags.contains("bitcoin"))
    }

    func testMentionParsing() {
        let content = "Hello @alice and @bob"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        let mentions = inlines.compactMap { inline -> String? in
            if case let .mention(name) = inline {
                return name
            }
            return nil
        }

        XCTAssertEqual(mentions.count, 2)
        XCTAssertTrue(mentions.contains("alice"))
        XCTAssertTrue(mentions.contains("bob"))
    }

    // MARK: - Complex Content Tests

    func testMixedFormatting() {
        let content = "This has **bold** and *italic* and `code`"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        XCTAssertGreaterThan(inlines.count, 1)

        // Verify we have bold, italic, and code elements
        var hasBold = false
        var hasItalic = false
        var hasCode = false

        for inline in inlines {
            switch inline {
            case .bold: hasBold = true
            case .italic: hasItalic = true
            case .code: hasCode = true
            default: break
            }
        }

        XCTAssertTrue(hasBold, "Should have bold formatting")
        XCTAssertTrue(hasItalic, "Should have italic formatting")
        XCTAssertTrue(hasCode, "Should have code formatting")
    }

    func testMultipleBlocks() {
        let content = """
        # Heading

        This is a paragraph.

        - List item 1
        - List item 2

        ```
        code block
        ```
        """
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 4)

        guard case .heading = blocks[0] else {
            XCTFail("Expected heading")
            return
        }

        guard case .paragraph = blocks[1] else {
            XCTFail("Expected paragraph")
            return
        }

        guard case .list = blocks[2] else {
            XCTFail("Expected list")
            return
        }

        guard case .codeBlock = blocks[3] else {
            XCTFail("Expected code block")
            return
        }
    }

    func testNestedFormatting() {
        let content = "**bold with *italic* inside**"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        // Should have bold element containing italic
        guard case let .bold(boldInlines) = inlines[0] else {
            XCTFail("Expected bold element")
            return
        }

        let hasItalic = boldInlines.contains { inline in
            if case .italic = inline { return true }
            return false
        }
        XCTAssertTrue(hasItalic, "Bold should contain italic")
    }

    // MARK: - Edge Cases

    func testEmptyContent() {
        let content = ""
        let blocks = MarkdownParser.parse(content)
        XCTAssertEqual(blocks.count, 0)
    }

    func testOnlyWhitespace() {
        let content = "   \n\n   \n"
        let blocks = MarkdownParser.parse(content)
        XCTAssertEqual(blocks.count, 0)
    }

    func testUnclosedBold() {
        let content = "**This is unclosed"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        // Should be treated as plain text
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text")
            return
        }
        XCTAssertTrue(text.contains("**"))
    }

    func testUnclosedItalic() {
        let content = "*This is unclosed"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        // Should be treated as plain text
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text")
            return
        }
        XCTAssertTrue(text.contains("*"))
    }

    func testUnclosedInlineCode() {
        let content = "`This is unclosed"
        let blocks = MarkdownParser.parse(content)

        XCTAssertEqual(blocks.count, 1)
        guard case let .paragraph(inlines) = blocks[0] else {
            XCTFail("Expected paragraph")
            return
        }

        // Should be treated as plain text
        guard case let .text(text) = inlines[0] else {
            XCTFail("Expected text")
            return
        }
        XCTAssertTrue(text.contains("`"))
    }
}
