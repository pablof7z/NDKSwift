import SwiftUI

/// Pill hashtag - shows tag in a colored pill
public struct PillHashtagView: HashtagRenderer {
    public let tag: String
    public let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    public init(tag: String, onTap: HashtagTapHandler? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    public var body: some View {
        Text("#\(tag)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .cornerRadius(12)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}
