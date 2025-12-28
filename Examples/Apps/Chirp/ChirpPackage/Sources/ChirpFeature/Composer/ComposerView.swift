import SwiftUI
import PhotosUI
import NDKSwiftCore
import NDKSwiftUI
import NDKSwiftNostrDB

// MARK: - ComposerView

public struct ComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let ndk: NDK
    let replyToEvent: NDKEvent?

    // Content state
    @State private var content: String = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    // Media upload state
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var uploadedMedia: [BlossomBlob] = []
    @State private var isUploadingMedia = false
    @State private var uploadProgress: Double = 0

    // Mention autocomplete state
    @State private var mentionQuery: String?
    @State private var mentionSuggestions: [MentionSuggestion] = []
    @State private var isLoadingMentions = false
    @State private var mentionSearchTask: Task<Void, Never>?

    // Draft persistence
    private static let draftKey = "com.ndkswift.Chirp.composerDraft"
    private static let replyDraftKeyPrefix = "com.ndkswift.Chirp.composerReplyDraft"

    public init(ndk: NDK, replyTo: NDKEvent? = nil) {
        self.ndk = ndk
        self.replyToEvent = replyTo
    }

    private var draftStorageKey: String {
        if let replyId = replyToEvent?.id {
            return "\(Self.replyDraftKeyPrefix).\(replyId)"
        }
        return Self.draftKey
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Reply indicator
                if let replyTo = replyToEvent {
                    replyIndicator(event: replyTo)
                }

                // Main content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Composer header with avatar
                        composerHeader

                        // Text editor
                        textEditorSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(replyToEvent != nil ? "Reply" : "New Post")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    publishButton
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 4, matching: .images) {
                        Image(systemName: "photo")
                    }

                    Button {
                        insertAtSymbol()
                    } label: {
                        Image(systemName: "at")
                    }

                    Spacer()

                    Text("\(content.count)")
                        .font(.caption)
                        .foregroundStyle(content.count > 280 ? .orange : .secondary)
                }
            }
            .toolbarRole(.editor)
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                isTextFieldFocused = true
                loadDraft()
            }
            .onChange(of: content) { _, newContent in
                saveDraft(newContent)
                detectMentionQuery(in: newContent)
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await processSelectedPhotos(newItems)
                }
            }
        }
    }

    // MARK: - Reply Indicator

    private func replyIndicator(event: NDKEvent) -> some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Replying to")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("@\(ndk.profile(for: event.pubkey).displayName ?? "...")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }

                Text(event.content.prefix(100) + (event.content.count > 100 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Composer Header

    private var composerHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            if let pubkey = ndk.sessionData?.pubkey {
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 44)
            }

            Spacer()
        }
    }

    // MARK: - Text Editor Section

    private var textEditorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Placeholder
                if content.isEmpty {
                    Text(replyToEvent != nil ? "Write your reply..." : "What's happening?")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }

                // Text editor with transparent background
                TextEditor(text: $content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .focused($isTextFieldFocused)
            }

            // Mention autocomplete suggestions
            if !mentionSuggestions.isEmpty {
                mentionSuggestionsView
            }

            // Uploaded media preview
            if !uploadedMedia.isEmpty {
                uploadedMediaPreview
            }

            // Upload progress indicator
            if isUploadingMedia {
                uploadProgressView
            }
        }
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(mentionSuggestions) { suggestion in
                Button {
                    insertMention(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        NDKUIProfilePicture(ndk: ndk, pubkey: suggestion.pubkey, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.displayName ?? suggestion.name ?? "Unknown")
                                .font(.subheadline.weight(.medium))

                            if let name = suggestion.name, suggestion.displayName != nil {
                                Text("@\(name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if suggestion.id != mentionSuggestions.last?.id {
                    Divider()
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .padding(.top, 8)
    }

    // MARK: - Uploaded Media Preview

    private var uploadedMediaPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(uploadedMedia.enumerated()), id: \.element.sha256) { index, blob in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: blob.url)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.gray.opacity(0.3))
                                    .frame(width: 80, height: 80)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                            case .empty:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.gray.opacity(0.3))
                                    .frame(width: 80, height: 80)
                                    .overlay {
                                        ProgressView()
                                    }
                            @unknown default:
                                EmptyView()
                            }
                        }

                        // Remove button
                        Button {
                            removeMedia(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Upload Progress

    private var uploadProgressView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.blue)

            Text("Uploading...")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 12)
    }

    private func insertAtSymbol() {
        // Add @ at current position, triggering mention detection
        if content.isEmpty || content.hasSuffix(" ") || content.hasSuffix("\n") {
            content += "@"
        } else {
            content += " @"
        }
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        Button {
            Task {
                await publish()
            }
        } label: {
            if isPublishing {
                ProgressView()
                    .tint(.white)
            } else {
                Text("Post")
                    .font(.headline)
            }
        }
        .disabled(!canPublish)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(canPublish ? AnyShapeStyle(ChirpGradients.primary) : AnyShapeStyle(Color.gray.opacity(0.3)))
        }
    }

    private var canPublish: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPublishing && !isUploadingMedia
    }

    // MARK: - Publishing

    private func publish() async {
        guard canPublish else { return }

        isPublishing = true
        errorMessage = nil

        let ndk = self.ndk
        let replyTo = self.replyToEvent
        let contentText = self.content
        let media = self.uploadedMedia

        do {
            let event: NDKEvent = try await Task { @MainActor in
                let builder: NDKEventBuilder

                if let replyTo = replyTo {
                    builder = NDKEventBuilder.reply(to: replyTo, ndk: ndk)
                        .content(contentText)
                } else {
                    builder = NDKEventBuilder(ndk: ndk)
                        .kind(EventKind.textNote)
                        .content(contentText)
                }

                // Add media imeta tags
                for blob in media {
                    _ = builder.imetaTag(from: blob)
                }

                return try await builder.build()
            }.value

            _ = try await Task { @MainActor in
                try await ndk.publish(event)
            }.value

            // Clear draft on success
            clearDraft()

            isPublishing = false
            dismiss()
        } catch {
            isPublishing = false
            errorMessage = "Failed to publish: \(error.localizedDescription)"
        }
    }

    // MARK: - Draft Persistence

    private func loadDraft() {
        if let saved = UserDefaults.standard.string(forKey: draftStorageKey) {
            content = saved
        }
    }

    private func saveDraft(_ text: String) {
        if text.isEmpty {
            UserDefaults.standard.removeObject(forKey: draftStorageKey)
        } else {
            UserDefaults.standard.set(text, forKey: draftStorageKey)
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
    }

    // MARK: - Mention Detection

    private func detectMentionQuery(in text: String) {
        // Look for @ that starts a word at end of content
        guard let atRange = text.range(of: "@", options: .backwards) else {
            mentionQuery = nil
            mentionSuggestions = []
            return
        }

        let afterAt = String(text[atRange.upperBound...])

        // Check if there's no space between @ and end
        if afterAt.contains(" ") || afterAt.contains("\n") {
            mentionQuery = nil
            mentionSuggestions = []
            return
        }

        // Check that @ is at start or preceded by whitespace
        let beforeAt = text[..<atRange.lowerBound]
        if !beforeAt.isEmpty && beforeAt.last?.isWhitespace != true {
            mentionQuery = nil
            mentionSuggestions = []
            return
        }

        mentionQuery = afterAt
        searchProfiles(query: afterAt)
    }

    private func searchProfiles(query: String) {
        mentionSearchTask?.cancel()
        isLoadingMentions = true

        mentionSearchTask = Task {
            guard let cache = ndk.cache as? NDKNostrDBCache else {
                mentionSuggestions = []
                isLoadingMentions = false
                return
            }

            // If query is empty, show follow list or recent profiles
            let pubkeys: [String]
            if query.isEmpty {
                // Show users from follow list as default suggestions
                if let followList = ndk.sessionData?.followList, !followList.isEmpty {
                    pubkeys = Array(followList.prefix(8))
                } else {
                    // Fall back to searching with empty string (returns recent profiles)
                    pubkeys = await cache.searchProfiles("", limit: 8)
                }
            } else {
                pubkeys = await cache.searchProfiles(query, limit: 8)
            }

            guard !Task.isCancelled else { return }

            var suggestions: [MentionSuggestion] = []
            for pubkey in pubkeys {
                let profile = ndk.profile(for: pubkey)
                suggestions.append(MentionSuggestion(
                    pubkey: pubkey,
                    displayName: profile.displayName,
                    name: profile.name,
                    picture: profile.pictureURL?.absoluteString
                ))
            }

            mentionSuggestions = suggestions
            isLoadingMentions = false
        }
    }

    private func insertMention(_ suggestion: MentionSuggestion) {
        guard mentionQuery != nil else { return }

        // Convert pubkey to npub
        let npub = (try? Bech32.npub(from: suggestion.pubkey)) ?? suggestion.pubkey

        // Find and replace @query (or just @) with nostr:npub format
        let searchPattern = mentionQuery!.isEmpty ? "@" : "@\(mentionQuery!)"
        if let atRange = content.range(of: searchPattern, options: .backwards) {
            content = content.replacingCharacters(in: atRange, with: "nostr:\(npub) ")
        }

        mentionQuery = nil
        mentionSuggestions = []
    }

    // MARK: - Media Upload

    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }

            await uploadMedia(data: data)
        }

        // Clear selection after processing
        selectedPhotoItems = []
    }

    private func uploadMedia(data: Data) async {
        isUploadingMedia = true
        uploadProgress = 0
        errorMessage = nil

        let ndk = self.ndk

        do {
            let serverURL = await getBlossomServer()

            let blob = try await Task { @MainActor in
                try await ndk.blossomClient.upload(
                    data: data,
                    mimeType: nil, // Auto-detect
                    to: serverURL,
                    ndk: ndk
                )
            }.value

            uploadedMedia.append(blob)

            // Append URL to content
            if !content.isEmpty && !content.hasSuffix(" ") && !content.hasSuffix("\n") {
                content += " "
            }
            content += blob.url

            isUploadingMedia = false
            uploadProgress = 1.0
        } catch {
            isUploadingMedia = false
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }

    private func getBlossomServer() async -> String {
        let ndk = self.ndk

        // Check for user's configured blossom servers (kind 10063)
        guard let signer = ndk.signer else {
            return "https://blossom.primal.net"
        }

        do {
            let pubkey = try await signer.pubkey
            let events = await Task { @MainActor in
                await ndk.fetchEvents(
                    filter: NDKFilter(authors: [pubkey], kinds: [10063], limit: 1),
                    cachePolicy: .cacheWithNetwork,
                    timeout: 5.0
                )
            }.value

            if let serverList = events.first {
                // Extract server URLs from r tags
                let servers = serverList.tags
                    .filter { $0.first == "r" && $0.count > 1 }
                    .map { $0[1] }

                if let firstServer = servers.first {
                    return firstServer
                }
            }
        } catch {
            // Fall back to default
        }

        return "https://blossom.primal.net"
    }

    private func removeMedia(at index: Int) {
        guard index < uploadedMedia.count else { return }
        let blob = uploadedMedia[index]
        uploadedMedia.remove(at: index)

        // Remove URL from content if present
        content = content.replacingOccurrences(of: blob.url, with: "")
        content = content.replacingOccurrences(of: "  ", with: " ")
        content = content.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - MentionSuggestion

struct MentionSuggestion: Identifiable, Equatable {
    var id: String { pubkey }
    let pubkey: String
    let displayName: String?
    let name: String?
    let picture: String?
}
