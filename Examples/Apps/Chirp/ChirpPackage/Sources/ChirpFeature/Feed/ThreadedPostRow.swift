import SwiftUI
import UIKit
import NDKSwiftCore
import NDKSwiftUI

enum ThreadPosition {
    case ancestor
    case active
    case reply
}

struct ThreadedPostRow: View {
    @Environment(ChirpState.self) private var state
    let ndk: NDK
    let event: NDKEvent
    let position: ThreadPosition
    let hasConnectionAbove: Bool
    let hasConnectionBelow: Bool

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?
    @State private var repostState: RepostState?
    @State private var showSigningRequiredAlert = false

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
                            Text(profile?.displayName ?? "...")
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
                        repostButton
                        actionButton(icon: "heart")
                        actionButton(icon: "bolt")
                        Spacer()
                        moreMenu
                    }
                    .padding(.top, 8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            if position != .ancestor {
                Divider()
                    .padding(.leading, 68)
            }
        }
        .background(alignment: .topLeading) {
            // Single continuous thread line behind avatar
            // Line X: 16 padding + 19 (center of 40px avatar - 1) = 35
            // Avatar top: 12 padding + 8 spacing = 20
            // Avatar bottom: 20 + 40 = 60
            if hasConnectionAbove || hasConnectionBelow {
                VStack(spacing: 0) {
                    // Line segment above avatar (or spacer if no connection above)
                    if hasConnectionAbove {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 2, height: 20)
                    } else {
                        Spacer()
                            .frame(height: 20)
                    }

                    // Gap for avatar (40px)
                    Spacer()
                        .frame(height: 40)

                    // Line segment below avatar (extends to bottom)
                    if hasConnectionBelow {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.leading, 35)
            }
        }
        .task {
            // Load profile and hold reference so SwiftUI observes changes
            profile = ndk.profile(for: event.pubkey)

            // Initialize and start repost state observation
            print("[PostRow] Creating RepostState - ndk.signer: \(ndk.signer == nil ? "nil" : "present")")
            let state = RepostState(ndk: ndk, event: event)
            repostState = state
            await state.start()
        }
    }

    private var repostButton: some View {
        Button {
            if state.authManager.canSign {
                Task {
                    do {
                        try await repostState?.toggle()
                    } catch {
                        print("Repost failed: \(error)")
                    }
                }
            } else {
                showSigningRequiredAlert = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.subheadline)
                if let count = repostState?.count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                }
            }
            .foregroundStyle(repostState?.hasReposted == true ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .alert("Signing Required", isPresented: $showSigningRequiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need to login with a signing-capable account to repost.")
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

    private var moreMenu: some View {
        Menu {
            Button {
                if let bech32 = try? Bech32.note(from: event.id) {
                    UIPasteboard.general.string = bech32
                }
            } label: {
                Label("Copy Note ID", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var relativeTime: String {
        formatRelativeTime(event.createdAt)
    }
}

// MARK: - Active Post View (Emphasized)

struct ActivePostView: View {
    @Environment(ChirpState.self) private var state
    let ndk: NDK
    let event: NDKEvent
    let hasConnectionAbove: Bool
    let hasConnectionBelow: Bool

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?
    @State private var repostState: RepostState?
    @State private var showSigningRequiredAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar column - offset to center 48px avatar on same line as 40px avatars
                NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 48)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .frame(width: 40, alignment: .top)
                .offset(x: -4)

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                        Text(profile?.displayName ?? "...")
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

            Divider()

            // Action bar - matches ThreadedPostRow layout
            HStack(spacing: 24) {
                actionButton(icon: "bubble.right")
                repostButton
                actionButton(icon: "heart")
                actionButton(icon: "bolt")
                Spacer()
                moreMenu
            }
            .padding(.leading, 68) // Align with content (16 padding + 40 avatar + 12 spacing)
            .padding(.trailing, 16)
            .padding(.vertical, 12)

            Divider()
        }
        .background(alignment: .topLeading) {
            // Thread line - aligned with ThreadedPostRow (x=35)
            // Avatar top: 12 padding + 12 spacing = 24
            // Avatar bottom: 24 + 48 = 72
            if hasConnectionAbove || hasConnectionBelow {
                VStack(spacing: 0) {
                    // Line segment above avatar
                    if hasConnectionAbove {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 2, height: 24)
                    } else {
                        Spacer()
                            .frame(height: 24)
                    }

                    // Gap for avatar (48px)
                    Spacer()
                        .frame(height: 48)

                    // Line segment below avatar (extends to bottom)
                    if hasConnectionBelow {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.leading, 35) // Same X position as ThreadedPostRow
            }
        }
        .background(Color(.systemBackground))
        .task {
            // Load profile and hold reference so SwiftUI observes changes
            profile = ndk.profile(for: event.pubkey)

            // Initialize and start repost state observation
            print("[PostRow] Creating RepostState - ndk.signer: \(ndk.signer == nil ? "nil" : "present")")
            let state = RepostState(ndk: ndk, event: event)
            repostState = state
            await state.start()
        }
    }

    private var repostButton: some View {
        Button {
            if state.authManager.canSign {
                Task {
                    do {
                        try await repostState?.toggle()
                    } catch {
                        print("Repost failed: \(error)")
                    }
                }
            } else {
                showSigningRequiredAlert = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.subheadline)
                if let count = repostState?.count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                }
            }
            .foregroundStyle(repostState?.hasReposted == true ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .alert("Signing Required", isPresented: $showSigningRequiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need to login with a signing-capable account to repost.")
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

    private var moreMenu: some View {
        Menu {
            Button {
                if let bech32 = try? Bech32.note(from: event.id) {
                    UIPasteboard.general.string = bech32
                }
            } label: {
                Label("Copy Note ID", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
