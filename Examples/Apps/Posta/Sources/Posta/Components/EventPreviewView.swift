import SwiftUI
import NDKSwift

/// View for displaying previews of Nostr events (nevent, note mentions)
struct EventPreviewView: View {
    let eventReference: EventReference
    
    @Environment(NDKManager.self) var ndkManager
    @State private var event: NDKEvent?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var eventTask: Task<Void, Never>?
    
    enum EventReference: Hashable {
        case eventId(String)
        case note(String)
        case nevent(String)
    }
    
    var body: some View {
        Group {
            if let event = event {
                // Render based on event kind
                switch event.kind {
                case EventKind.textNote:
                    TextNotePreview(event: event)
                default:
                    UnknownEventPreview(event: event)
                }
            } else if isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading event...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(12)
            } else if loadError != nil {
                // Error state
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Could not load event")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(12)
            }
        }
        .onAppear {
            loadEvent()
        }
        .onDisappear {
            eventTask?.cancel()
        }
    }
    
    private func loadEvent() {
        guard let ndk = ndkManager.ndk else { return }
        
        eventTask = Task {
            do {
                let eventId: String
                
                switch eventReference {
                case .eventId(let id):
                    eventId = id
                case .note(let bech32):
                    eventId = try Bech32.eventId(from: bech32)
                case .nevent(let bech32):
                    // TODO: Decode nevent to get event ID and relay hints
                    // For now, just try to extract event ID
                    eventId = String(bech32.dropFirst(7).prefix(64)) // Rough extraction
                }
                
                // Create filter for this specific event
                let filter = NDKFilter(
                    ids: [eventId],
                    limit: 1
                )
                
                // Use observe with maxAge > 0 to fetch and close
                let dataSource = ndk.observe(filter: filter, maxAge: 300) // 5 min cache
                
                for await fetchedEvent in dataSource.events {
                    await MainActor.run {
                        self.event = fetchedEvent
                        self.isLoading = false
                    }
                    break // We only need the first event
                }
                
                // If no event found after EOSE
                await MainActor.run {
                    if self.event == nil {
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.loadError = error
                    self.isLoading = false
                }
            }
        }
    }
}

/// Preview for text notes (kind:1) - embedded tweet style
struct TextNotePreview: View {
    let event: NDKEvent
    
    @Environment(NDKManager.self) var ndkManager
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author info
            HStack(spacing: 8) {
                // Avatar
                if let avatarURL = profile?.picture, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile?.displayName ?? profile?.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("@\(profile?.name ?? String(event.pubkey.prefix(8)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Timestamp
                Text(event.createdAt.formatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Content
            RichTextInline(
                content: event.content,
                tags: event.tags,
                currentUser: nil
            )
            .font(.system(size: 14))
            .lineLimit(6)
            .foregroundColor(.primary)
            
            // Interaction hints
            HStack {
                Image(systemName: "bubble.left")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Image(systemName: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Image(systemName: "heart")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color(.secondarySystemFill))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            loadProfile()
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
    
    private func loadProfile() {
        guard let ndk = ndkManager.ndk else { return }
        
        profileTask = Task {
            let profileStream = await ndk.profileManager.observe(for: event.pubkey, maxAge: TimeConstants.hour)
            
            for await profile in profileStream {
                if let profile = profile {
                    await MainActor.run {
                        self.profile = profile
                    }
                    break
                }
            }
        }
    }
}

/// Preview for unknown event kinds with alt tag support
struct UnknownEventPreview: View {
    let event: NDKEvent
    
    @State private var showFullContent = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Event")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Kind \(event.kind)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Content or alt tag
            if let altContent = event.tagValue("alt") {
                // Show alt tag content
                Text(altContent)
                    .font(.system(size: 14))
                    .lineLimit(showFullContent ? nil : 3)
                    .foregroundColor(.primary)
            } else {
                // Show preview prompt or content
                if showFullContent {
                    Text(event.content)
                        .font(.system(size: 14))
                        .lineLimit(10)
                        .foregroundColor(.primary)
                } else {
                    Text("This is a kind \(event.kind) event. Tap to preview the content.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemFill))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if event.tagValue("alt") == nil {
                withAnimation {
                    showFullContent.toggle()
                }
            }
        }
    }
}