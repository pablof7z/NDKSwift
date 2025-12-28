import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

// MARK: - Profile Search Result Row

/// A row displaying a profile search result
struct ProfileSearchResultRow: View {
    let ndk: NDK
    let pubkey: String

    @State private var profile: NDKProfile?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 48)

            // Profile info
            VStack(alignment: .leading, spacing: 4) {
                // Display name
                Text(profile?.displayName ?? shortenedPubkey)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                // NIP-05 or shortened pubkey
                if let nip05 = profile?.metadata?.nip05, !nip05.isEmpty {
                    Text(nip05)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if profile != nil {
                    Text(shortenedPubkey)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // About (if available)
                if let about = profile?.metadata?.about, !about.isEmpty {
                    Text(about)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .task {
            profile = ndk.profile(for: pubkey)
        }
    }

    private var shortenedPubkey: String {
        if pubkey.count > 16 {
            return "\(pubkey.prefix(8))...\(pubkey.suffix(8))"
        }
        return pubkey
    }
}

// MARK: - Event Search Result Row

/// A row displaying an event search result
struct EventSearchResultRow: View {
    let ndk: NDK
    let event: NDKEvent

    @State private var profile: NDKProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 36)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Header row
                    HStack(spacing: 4) {
                        Text(profile?.displayName ?? shortenedPubkey)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(relativeTime)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    // Content preview
                    Text(event.content)
                        .font(.body)
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Divider
            Divider()
                .padding(.leading, 64)
        }
        .contentShape(Rectangle())
        .task {
            profile = ndk.profile(for: event.pubkey)
        }
    }

    private var shortenedPubkey: String {
        let pk = event.pubkey
        if pk.count > 16 {
            return "\(pk.prefix(8))...\(pk.suffix(8))"
        }
        return pk
    }

    private var relativeTime: String {
        let now = Date()
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        let interval = now.timeIntervalSince(eventDate)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: eventDate)
        }
    }
}

