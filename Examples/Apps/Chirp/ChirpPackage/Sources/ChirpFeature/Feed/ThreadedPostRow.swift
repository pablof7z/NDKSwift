import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

enum ThreadPosition {
    case ancestor
    case active
    case reply
}

struct ThreadedPostRow: View {
    let ndk: NDK
    let event: NDKEvent
    let position: ThreadPosition
    let hasConnectionAbove: Bool
    let hasConnectionBelow: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar column
                NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .frame(width: 40, alignment: .top)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                            Text(ndk.profile(for: event.pubkey).displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(relativeTime)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    NDKRichText(content: event.content, tags: event.tags)
                        .ndk(ndk)
                        .font(.body)
                        .lineLimit(position == .ancestor ? 3 : nil)

                    // Compact action bar
                    HStack(spacing: 24) {
                        actionButton(icon: "bubble.right")
                        actionButton(icon: "arrow.2.squarepath")
                        actionButton(icon: "heart")
                        actionButton(icon: "bolt")
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(alignment: .topLeading) {
                threadingLines
            }

            if position != .ancestor {
                Divider()
                    .padding(.leading, 68)
            }
        }
    }

    private var threadingLines: some View {
        GeometryReader { geometry in
            let avatarCenterX: CGFloat = 36 // 16 padding + 20 half of 40px avatar
            let avatarTopY: CGFloat = 20 // 12 padding + 8 top spacing
            let avatarBottomY: CGFloat = 60 // avatarTopY + 40px avatar

            // Line above avatar
            if hasConnectionAbove {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 2, height: avatarTopY)
                    .position(x: avatarCenterX, y: avatarTopY / 2)
            }

            // Line below avatar
            if hasConnectionBelow {
                let lineHeight = geometry.size.height - avatarBottomY
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 2, height: max(0, lineHeight))
                    .position(x: avatarCenterX, y: avatarBottomY + lineHeight / 2)
            }
        }
    }

    private func actionButton(icon: String) -> some View {
        Button {
            // Actions not implemented yet
        } label: {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var relativeTime: String {
        formatRelativeTime(event.createdAt)
    }
}

// MARK: - Active Post View (Emphasized)

struct ActivePostView: View {
    let ndk: NDK
    let event: NDKEvent
    let hasConnectionAbove: Bool
    let hasConnectionBelow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar column
                NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 48)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .frame(width: 48, alignment: .top)

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                        Text(ndk.profile(for: event.pubkey).displayName)
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.plain)

                    // Content with larger font
                    NDKRichText(content: event.content, tags: event.tags)
                        .ndk(ndk)
                        .font(.title3)

                    // Timestamp
                    Text(Date(timeIntervalSince1970: TimeInterval(event.createdAt)), format: .dateTime.month().day().year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .topLeading) {
                if hasConnectionAbove {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2, height: 36)
                        .offset(x: 40, y: 0) // Center of avatar (16 padding + 24 half of 48)
                }
            }

            Divider()

            // Action bar
            HStack(spacing: 0) {
                actionButton(icon: "bubble.right", label: "Reply")
                Spacer()
                actionButton(icon: "arrow.2.squarepath", label: "Repost")
                Spacer()
                actionButton(icon: "heart", label: "Like")
                Spacer()
                actionButton(icon: "bolt", label: "Zap")
                Spacer()
                actionButton(icon: "square.and.arrow.up", label: "Share")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
        }
        .background(Color(.systemBackground))
    }

    private func actionButton(icon: String, label: String) -> some View {
        Button {
            // Actions not implemented yet
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(label)
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Utilities

private func formatRelativeTime(_ timestamp: Timestamp) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let now = Date()
    let interval = now.timeIntervalSince(date)

    if interval < 60 {
        return "now"
    } else if interval < 3600 {
        let minutes = Int(interval / 60)
        return "\(minutes)m"
    } else if interval < 86400 {
        let hours = Int(interval / 3600)
        return "\(hours)h"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
