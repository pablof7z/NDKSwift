import SwiftUI

/// Compact hashtag - smaller, muted styling
public struct CompactHashtagView: HashtagRenderer {
    public let tag: String
    public let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    public init(tag: String, onTap: HashtagTapHandler? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    public var body: some View {
        Text("#\(tag)")
            .font(.footnote)
            .foregroundColor(.secondary)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}
