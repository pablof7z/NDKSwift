import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Live feed of Nostr notes that exercises the relay intelligence layer
/// Fetching notes triggers outbox model and relay selection
public struct FeedView: View {
    let ndk: NDK

    @State private var dataSource: NDKSubscription<NDKEvent>?
    @State private var selectedPubkey: String?
    @State private var isLoadingProfile = false

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            HStack {
                if let ds = dataSource {
                    Text("\(ds.data.count) notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))

            // Feed list
            if let ds = dataSource {
                if ds.data.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No notes yet")
                            .foregroundColor(.secondary)
                        Text("Pull to refresh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(ds.data, id: \.id) { event in
                            NoteRow(event: event, ndk: ndk, onAuthorTap: { pubkey in
                                selectedPubkey = pubkey
                            })
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        refresh()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Initializing feed...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            initializeDataSource()
        }
        .sheet(item: $selectedPubkey) { pubkey in
            ProfileSheet(ndk: ndk, pubkey: pubkey)
        }
    }

    private func initializeDataSource() {
        // Subscribe to recent text notes (kind 1)
        dataSource = NDKSubscription(
            ndk: ndk,
            filter: NDKFilter(kinds: [1], limit: 50)
        )
    }

    private func refresh() {
        // Re-initialize to refresh
        dataSource = nil
        initializeDataSource()
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let event: NDKEvent
    let ndk: NDK
    let onAuthorTap: (String) -> Void

    @State private var authorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author row
            HStack {
                // Author avatar placeholder
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(authorInitial)
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName ?? truncatedPubkey)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Tap to view profile (exercises outbox)
                Button(action: { onAuthorTap(event.pubkey) }) {
                    Image(systemName: "person.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onAuthorTap(event.pubkey)
            }

            // Content - use markdown renderer for Nostr entities
            NDKUIMarkdownRenderer(event.content, ndk: ndk)
                .markdownStyle(.compact)

            // Tags indicator
            if !event.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(extractHashtags(), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            await loadAuthorName()
        }
    }

    private var authorInitial: String {
        if let name = authorName, !name.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return String(event.pubkey.prefix(1)).uppercased()
    }

    private var truncatedPubkey: String {
        let pubkey = event.pubkey
        return String(pubkey.prefix(8)) + "..." + String(pubkey.suffix(4))
    }

    private var timeAgo: String {
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        let interval = Date().timeIntervalSince(eventDate)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    private func extractHashtags() -> [String] {
        event.tags
            .filter { $0.first == "t" }
            .compactMap { $0.dropFirst().first }
            .prefix(3)
            .map { String($0) }
    }

    private func loadAuthorName() async {
        // This exercises the outbox model - fetching profile from author's relays
        if let user = ndk.getUser(event.pubkey) {
            if let profile = await user.profile {
                authorName = profile.displayName
            }
        }
    }
}

// MARK: - Profile Sheet

struct ProfileSheet: View {
    let ndk: NDK
    let pubkey: String

    @State private var profile: NDKProfile?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Loading profile...")
                        .frame(maxHeight: .infinity)
                } else if let profile = profile {
                    // Profile avatar
                    AsyncImage(url: profile.pictureURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.blue)
                            }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())

                    // Name
                    Text(profile.displayName)
                        .font(.title2.bold())

                    // NIP-05
                    if let nip05 = profile.nip05 {
                        Text(nip05)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // About
                    if let about = profile.about, !about.isEmpty {
                        Text(about)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Pubkey
                    VStack(spacing: 4) {
                        Text("Public Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(pubkey)
                            .font(.caption2.monospaced())
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    Spacer()

                    Text("Loading this profile exercises the outbox model")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Profile not found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadProfile()
        }
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }

        if let user = ndk.getUser(pubkey) {
            profile = await user.profile
        }
    }
}

// MARK: - String Extension for Sheet

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Preview

#if DEBUG
struct FeedView_Previews: PreviewProvider {
    static var previews: some View {
        FeedView(ndk: NDK())
    }
}
#endif
