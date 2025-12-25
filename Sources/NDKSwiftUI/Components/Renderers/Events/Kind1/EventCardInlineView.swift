import NDKSwiftCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Event card inline - minimal inline presentation
public struct EventCardInlineView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let ndk = ndk {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 24)
                }

                if let ndk = ndk {
                    NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                        .font(.caption.weight(.medium))
                } else {
                    Text("@\(String(event.pubkey.prefix(8)))...")
                        .font(.caption.weight(.medium))
                }

                Spacer()

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(event.content)
                .font(.caption)
                .lineLimit(3)
        }
        .padding(12)
        .background(Color.ndkSecondaryBackground.opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
