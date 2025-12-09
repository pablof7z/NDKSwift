// PostCard.swift
import SwiftUI
import NDKSwift
import NDKSwiftUI

public struct PostCard: View {
    let event: NDKEvent
    let ndk: NDK

    @State private var isLiked = false

    public init(event: NDKEvent, ndk: NDK) {
        self.event = event
        self.ndk = ndk
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            postHeader
            postImage
            postActions
            postCaption
        }
    }

    private var postHeader: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                    .font(.subheadline.weight(.semibold))

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postImage: some View {
        Group {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(ProgressView())
                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isLiked = true
            }
        }
    }

    private var postActions: some View {
        HStack(spacing: 16) {
            Button {
                isLiked.toggle()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? OlasTheme.Colors.heartRed : .primary)
            }

            Button {
                // Comments action
            } label: {
                Image(systemName: "bubble.right")
            }

            Button {
                // Zap action
            } label: {
                Image(systemName: "bolt")
                    .foregroundStyle(OlasTheme.Colors.zapGold)
            }

            Spacer()
        }
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postCaption: some View {
        Group {
            if !event.content.isEmpty {
                HStack {
                    Text(event.content)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
