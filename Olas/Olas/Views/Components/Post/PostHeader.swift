import SwiftUI
import NDKSwift
import NDKSwiftUI

struct PostHeader: View {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?
    let onCopyId: () -> Void
    let onReport: () -> Void
    let onMute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            profilePictureButton

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    onProfileTap?(event.pubkey)
                } label: {
                    NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("post_author_name")

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            overflowMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("post_author_header")
    }

    private var profilePictureButton: some View {
        Button {
            onProfileTap?(event.pubkey)
        } label: {
            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("post_author_avatar")
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                onCopyId()
            } label: {
                Label("Copy ID", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                onReport()
            } label: {
                Label("Report", systemImage: "exclamationmark.triangle")
            }

            Button(role: .destructive) {
                onMute()
            } label: {
                Label("Mute Author", systemImage: "speaker.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}
