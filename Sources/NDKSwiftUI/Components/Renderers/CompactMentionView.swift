import NDKSwiftCore
import SwiftUI

/// Compact mention - just shows truncated npub, no profile loading
public struct CompactMentionView: MentionRenderer {
    public let pubkey: String
    public let npub: String
    public let onTap: MentionTapHandler?

    @Environment(\.onMentionTap) private var envOnTap

    public init(pubkey: String, npub: String, onTap: MentionTapHandler? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.onTap = onTap
    }

    public var body: some View {
        Text("@\(String(npub.prefix(12)))...")
            .font(.footnote.monospaced())
            .foregroundColor(.secondary)
            .onTapGesture {
                (onTap ?? envOnTap)?(pubkey)
            }
    }
}
