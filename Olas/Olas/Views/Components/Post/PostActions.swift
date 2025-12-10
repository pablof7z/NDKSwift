import SwiftUI
import NDKSwift

struct PostActions: View {
    let event: NDKEvent
    let ndk: NDK
    @Binding var isLiked: Bool
    let likeCount: Int
    let commentCount: Int
    let onLikeTap: () -> Void
    let onCommentTap: () -> Void
    let onAddToCollection: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            LikeButton(isLiked: $isLiked, likeCount: likeCount, onLike: onLikeTap)

            CommentButton(commentCount: commentCount, action: onCommentTap)

            ZapButton(event: event, ndk: ndk)

            Spacer()

            shareMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var shareMenu: some View {
        Menu {
            Button {
                onAddToCollection()
            } label: {
                Label("Add to Collection", systemImage: "rectangle.stack.badge.plus")
            }

            Button {
                onShare()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "paperplane")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
