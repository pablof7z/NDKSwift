import SwiftUI
import NDKSwiftCore

/// Default implementation of EventRenderer that displays embedded events
public struct DefaultEventView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let ndk = ndk {
                NDKUIEventView(ndk: ndk, event: event, style: .embedded, showInteractions: false)
            } else {
                // Fallback when no NDK available
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event: \(String(event.id.prefix(8)))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.content.prefix(100) + (event.content.count > 100 ? "..." : ""))
                        .font(.body)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
