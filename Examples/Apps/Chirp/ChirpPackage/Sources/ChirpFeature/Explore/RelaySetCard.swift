import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Card view for relay sets in the horizontal scroll
struct RelaySetCard: View {
    let ndk: NDK
    let relaySet: RelaySet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            iconView

            // Title
            Text(relaySet.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Creator
            HStack(spacing: 2) {
                Text("by")
                    .foregroundStyle(.secondary)
                NDKUIDisplayName(ndk: ndk, pubkey: relaySet.creatorPubkey)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .lineLimit(1)

            // Relay count
            Text("\(relaySet.relayCount) relay\(relaySet.relayCount == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)
        }
        .frame(width: 180, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var iconView: some View {
        Text(relaySet.icon)
            .font(.system(size: 20))
            .frame(width: 44, height: 44)
            .background(iconGradient)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var iconGradient: LinearGradient {
        switch relaySet.gradientType {
        case .general:
            return LinearGradient(
                colors: [Color(red: 0.19, green: 0.82, blue: 0.35), Color(red: 0, green: 0.78, blue: 0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .inbox:
            return LinearGradient(
                colors: [Color(red: 0.04, green: 0.52, blue: 1), Color(red: 0.37, green: 0.36, blue: 0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .outbox:
            return LinearGradient(
                colors: [Color(red: 1, green: 0.62, blue: 0.04), Color(red: 1, green: 0.22, blue: 0.37)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dm:
            return LinearGradient(
                colors: [Color(red: 1, green: 0.62, blue: 0.04), Color(red: 1, green: 0.22, blue: 0.37)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
