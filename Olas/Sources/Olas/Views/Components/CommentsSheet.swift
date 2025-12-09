import SwiftUI
import NDKSwift
import NDKSwiftUI

struct CommentsSheet: View {
    let event: NDKEvent
    let ndk: NDK
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var muteListManager: MuteListManager

    @State private var comments: [NDKEvent] = []
    @State private var newComment = ""
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool

    private var filteredComments: [NDKEvent] {
        comments.filter { !muteListManager.isMuted($0.pubkey) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list - streams in as they arrive
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredComments, id: \.id) { comment in
                            CommentRow(comment: comment, ndk: ndk)
                        }
                    }
                }

                Divider()

                // Input bar
                commentInput
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await loadComments()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    private var commentInput: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $newComment, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .focused($isInputFocused)

            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        newComment.isEmpty ? .secondary : OlasTheme.Colors.deepTeal
                    )
            }
            .disabled(newComment.isEmpty || isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func loadComments() async {
        // Fetch comments (kind 1111) that reference this event
        let filter = NDKFilter(
            kinds: [OlasConstants.EventKinds.comment],
            limit: 100
        )

        let subscription = ndk.subscribe(filter: filter)

        // Stream comments as they arrive
        for await commentEvent in subscription.events {
            // Check if comment references our event
            let referencesOurEvent = commentEvent.tags.contains { tag in
                tag.first == "e" && tag.count > 1 && tag[1] == event.id
            }

            if referencesOurEvent {
                // Insert in sorted position (oldest first for comments)
                let insertIndex = comments.firstIndex { commentEvent.createdAt < $0.createdAt } ?? comments.endIndex
                comments.insert(commentEvent, at: insertIndex)
            }
        }
    }

    private func sendComment() async {
        guard !newComment.isEmpty else { return }

        isSending = true
        let commentText = newComment
        newComment = ""

        do {
            let (newEvent, _) = try await ndk.publish { builder in
                builder
                    .kind(OlasConstants.EventKinds.comment)
                    .content(commentText)
                    .tag(["e", event.id, "", "root"])
                    .tag(["p", event.pubkey])
                    .tag(["k", "\(event.kind)"])
            }

            // Add to local list
            await MainActor.run {
                comments.append(newEvent)
                triggerHaptic()
            }
        } catch {
            // Restore comment text on error
            newComment = commentText
        }

        isSending = false
    }

    private func triggerHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
}

struct CommentRow: View {
    let comment: NDKEvent
    let ndk: NDK

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: comment.pubkey, size: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    NDKUIDisplayName(ndk: ndk, pubkey: comment.pubkey)
                        .font(.subheadline.weight(.semibold))

                    NDKUIRelativeTime(timestamp: comment.createdAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(comment.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                // Like button for comment
                Button {
                    // Like comment
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.caption)
                        Text("Like")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
