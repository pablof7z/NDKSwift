import NDKSwiftCore
import SwiftUI

/// Pill mention - shows name in a colored pill
public struct PillMentionView: MentionRenderer {
    public let pubkey: String
    public let npub: String
    public let onTap: MentionTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onMentionTap) private var envOnTap

    public init(pubkey: String, npub: String, onTap: MentionTapHandler? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Group {
                if let ndk = ndk {
                    NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                } else {
                    Text("@\(String(npub.prefix(8)))...")
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15))
        .foregroundColor(.blue)
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(pubkey)
        }
    }
}
