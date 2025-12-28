import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Card view for ranked relays from kind 10012 relay feeds
struct RankedRelayCard: View {
    let relay: RankedRelay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            iconView

            // Relay name
            Text(relay.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Description or URL
            Text(relay.description ?? relay.url)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Stats row
            HStack(spacing: 8) {
                // Appearance count
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                    Text("\(relay.appearanceCount)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.blue)

                // NIP-11 indicator
                if relay.hasNIP11Info {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("NIP-11")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.green)
                }
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var iconView: some View {
        Group {
            if let iconURL = relay.iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    relayIconPlaceholder
                }
            } else {
                relayIconPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var relayIconPlaceholder: some View {
        Text("📡")
            .font(.system(size: 20))
            .frame(width: 44, height: 44)
            .background(iconGradient)
    }

    private var iconGradient: LinearGradient {
        // Gradient based on score - higher score = more vibrant
        if relay.normalizedScore > 0.5 {
            return LinearGradient(
                colors: [Color(red: 0.04, green: 0.52, blue: 1), Color(red: 0.37, green: 0.36, blue: 0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if relay.normalizedScore > 0.2 {
            return LinearGradient(
                colors: [Color(red: 0.19, green: 0.82, blue: 0.35), Color(red: 0, green: 0.78, blue: 0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 0.5, green: 0.5, blue: 0.5), Color(red: 0.6, green: 0.6, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
