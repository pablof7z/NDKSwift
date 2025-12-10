import SwiftUI
import NDKSwift

struct PostCaption: View {
    let ndk: NDK
    let pubkey: String
    let content: String
    let likeCount: Int

    var body: some View {
        Group {
            if !content.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CaptionText(ndk: ndk, pubkey: pubkey, content: content)
                        .lineLimit(3)

                    if likeCount > 0 {
                        likeCountText
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else if likeCount > 0 {
                likeCountText
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private var likeCountText: some View {
        Text("\(likeCount) like\(likeCount == 1 ? "" : "s")")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

// MARK: - CaptionText

private struct CaptionText: View {
    let ndk: NDK
    let pubkey: String
    let content: String

    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    var body: some View {
        (Text(displayName).fontWeight(.semibold) + Text(" ") + Text(content))
            .font(.subheadline)
            .onAppear { loadProfile() }
            .onDisappear {
                profileTask?.cancel()
                profileTask = nil
            }
    }

    private var displayName: String {
        if let displayName = metadata?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let name = metadata?.name, !name.isEmpty {
            return name
        }
        let npub = NDKUser(pubkey: pubkey).npub
        return String(npub.prefix(16)) + "..."
    }

    private func loadProfile() {
        profileTask?.cancel()
        profileTask = nil
        profileTask = Task {
            for await metadata in await ndk.profileManager.subscribe(for: pubkey) {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.metadata = metadata
                }
            }
        }
    }
}
