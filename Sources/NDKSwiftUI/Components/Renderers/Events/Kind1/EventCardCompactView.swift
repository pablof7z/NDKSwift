import NDKSwiftCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Event card compact - compact presentation with avatar
public struct EventCardCompactView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let ndk = ndk {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let ndk = ndk {
                        NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("@\(String(event.pubkey.prefix(8)))...")
                            .font(.subheadline.weight(.semibold))
                    }

                    NDKUIRelativeTime(timestamp: event.createdAt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text(event.content)
                .font(.subheadline)
                .lineLimit(4)
        }
        .padding(12)
        .background(Color.ndkPrimaryBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
