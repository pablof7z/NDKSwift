import Foundation

/// Utility for grouping consecutive images in content arrays.
/// Used by both NDKUIRichTextView and NDKUIMarkdownView.
public enum ImageGroupingUtils {
    /// Groups consecutive image items, treating whitespace-only text as separators that don't break groups.
    /// - Parameters:
    ///   - items: The items to process
    ///   - getImageURL: Returns the image URL if the item is an image, nil otherwise
    ///   - isWhitespaceText: Returns true if the item is whitespace-only text
    /// - Returns: Array of grouped results where consecutive images become `.imageGroup([URL])`
    public static func groupConsecutiveImages<T>(
        _ items: [T],
        getImageURL: (T) -> URL?,
        isWhitespaceText: (T) -> Bool
    ) -> [GroupedResult<T>] {
        var result: [GroupedResult<T>] = []
        var pendingImages: [URL] = []
        var pendingWhitespace: [T] = []

        for item in items {
            if let imageURL = getImageURL(item) {
                // Image - add to pending group, discard whitespace between images
                pendingWhitespace = []
                pendingImages.append(imageURL)
            } else if isWhitespaceText(item) {
                // Whitespace-only text - might be between images
                if !pendingImages.isEmpty {
                    pendingWhitespace.append(item)
                } else {
                    result.append(.single(item))
                }
            } else {
                // Non-image, non-whitespace item - flush pending images
                if !pendingImages.isEmpty {
                    result.append(.imageGroup(pendingImages))
                    pendingImages = []
                }
                for ws in pendingWhitespace {
                    result.append(.single(ws))
                }
                pendingWhitespace = []
                result.append(.single(item))
            }
        }

        // Flush any remaining pending images
        if !pendingImages.isEmpty {
            result.append(.imageGroup(pendingImages))
        }
        // Trailing whitespace after images is discarded

        return result
    }

    /// Result of grouping operation - either a single item or a group of image URLs
    public enum GroupedResult<T> {
        case single(T)
        case imageGroup([URL])
    }
}
