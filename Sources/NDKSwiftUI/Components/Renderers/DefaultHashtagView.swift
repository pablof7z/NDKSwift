import SwiftUI

/// Default implementation of HashtagRenderer that displays hashtags with tap support
public struct DefaultHashtagView: HashtagRenderer {
    public let tag: String
    public let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    public init(tag: String, onTap: HashtagTapHandler? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    public var body: some View {
        Text("#\(tag)")
            .foregroundColor(.accentColor)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}
