import SwiftUI
import NDKSwift

#if canImport(UIKit)
import UIKit
#endif

struct OlasCaptionComposer: View {
    @Binding var caption: String
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    
    @State private var showMentions = false
    @State private var showHashtags = false
    @State private var currentWord = ""
    @State private var cursorPosition: Int = 0
    @State private var suggestedUsers: [NDKUser] = []
    @State private var suggestedProfiles: [String: NDKUserProfile] = [:]
    
    // Popular hashtags
    let popularHashtags = [
        "photography", "nostr", "art", "nature", "portrait",
        "streetphotography", "landscape", "blackandwhite", 
        "travel", "sunset", "architecture", "macro"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            Text("Caption")
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundColor(OlasDesign.Colors.text)
            
            // Caption input with custom editor
            ZStack(alignment: .topLeading) {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(OlasDesign.Colors.border, lineWidth: 1)
                    )
                
                // Text editor
                CaptionTextEditor(
                    text: $caption,
                    onWordChange: handleWordChange
                )
                .scrollContentBackground(.hidden)
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.text)
                .padding(OlasDesign.Spacing.sm)
            }
            .frame(minHeight: 100)
            
            // Suggestions
            if showMentions && !suggestedUsers.isEmpty {
                mentionSuggestions
            } else if showHashtags {
                hashtagSuggestions
            }
        }
    }
    
    @ViewBuilder
    private var mentionSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Suggestions")
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textTertiary)
                .padding(.horizontal, OlasDesign.Spacing.sm)
                .padding(.vertical, OlasDesign.Spacing.xs)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OlasDesign.Spacing.sm) {
                    ForEach(suggestedUsers.prefix(10), id: \.pubkey) { user in
                        Button(action: {
                            insertMention(user)
                            OlasDesign.Haptic.selection()
                        }) {
                            HStack(spacing: OlasDesign.Spacing.xs) {
                                // Avatar
                                if let profile = suggestedProfiles[user.pubkey] {
                                    OlasAvatar(
                                        url: profile.picture,
                                        size: 24,
                                        pubkey: user.pubkey
                                    )
                                } else {
                                    Circle()
                                        .fill(OlasDesign.Colors.surface)
                                        .frame(width: 24, height: 24)
                                }
                                
                                // Name
                                VStack(alignment: .leading, spacing: 0) {
                                    if let profile = suggestedProfiles[user.pubkey] {
                                        Text(profile.displayName ?? profile.name ?? "Unknown")
                                            .font(OlasDesign.Typography.caption)
                                            .foregroundColor(OlasDesign.Colors.text)
                                        
                                        if let name = profile.name {
                                            Text("@\(name)")
                                                .font(.system(size: 10))
                                                .foregroundColor(OlasDesign.Colors.textTertiary)
                                        }
                                    } else {
                                        Text(user.npub.prefix(16) + "...")
                                            .font(OlasDesign.Typography.caption)
                                            .foregroundColor(OlasDesign.Colors.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, OlasDesign.Spacing.sm)
                            .padding(.vertical, OlasDesign.Spacing.xs)
                            .background(OlasDesign.Colors.surface)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(OlasDesign.Colors.border, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.sm)
            }
            .frame(height: 44)
            .task {
                await loadProfilesForSuggestions()
            }
        }
        .background(OlasDesign.Colors.surface.opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var hashtagSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                ForEach(filteredHashtags, id: \.self) { tag in
                    Button(action: {
                        insertHashtag(tag)
                        OlasDesign.Haptic.selection()
                    }) {
                        Text("#\(tag)")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.primary)
                            .padding(.horizontal, OlasDesign.Spacing.sm)
                            .padding(.vertical, OlasDesign.Spacing.xs)
                            .background(OlasDesign.Colors.primary.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
            }
        }
    }
    
    private var filteredHashtags: [String] {
        let searchTerm = currentWord.dropFirst() // Remove #
        if searchTerm.isEmpty {
            return popularHashtags
        }
        return popularHashtags.filter { $0.lowercased().contains(searchTerm.lowercased()) }
    }
    
    private func handleWordChange(_ word: String, position: Int) {
        currentWord = word
        cursorPosition = position
        
        if word.hasPrefix("@") && word.count > 1 {
            showMentions = true
            showHashtags = false
            searchUsers(String(word.dropFirst()))
        } else if word.hasPrefix("#") {
            showMentions = false
            showHashtags = true
        } else {
            showMentions = false
            showHashtags = false
        }
    }
    
    private func searchUsers(_ query: String) {
        guard let ndk = nostrManager.ndk else { return }
        
        Task {
            // Search for users by name/username
            let filter = NDKFilter(
                kinds: [EventKind.metadata],
                limit: 20
            )
            
            // For now, use empty array as we need to implement proper subscription
            // TODO: Implement proper subscription to fetch metadata events
            let events: [NDKEvent] = []
            
            var users: [NDKUser] = []
            // Implement proper metadata search when subscription API is available
            // For now, return empty list
            
            await MainActor.run {
                self.suggestedUsers = users
            }
        }
    }
    
    private func loadProfilesForSuggestions() async {
        guard let profileManager = nostrManager.ndk?.profileManager else { return }
        
        for user in suggestedUsers {
            if suggestedProfiles[user.pubkey] == nil {
                Task {
                    for await profile in await profileManager.observe(for: user.pubkey, maxAge: 3600) {
                        await MainActor.run {
                            suggestedProfiles[user.pubkey] = profile
                        }
                        break // Only need the first profile
                    }
                }
            }
        }
    }
    
    private func insertMention(_ user: NDKUser) {
        // Replace the current @mention with the full mention
        let beforeCursor = String(caption.prefix(cursorPosition - currentWord.count))
        let afterCursor = String(caption.suffix(caption.count - cursorPosition))
        
        let mention = "@\(user.npub) "
        
        caption = beforeCursor + mention + afterCursor
        showMentions = false
        currentWord = ""
    }
    
    private func insertHashtag(_ tag: String) {
        // Replace the current #word with the full hashtag
        let beforeCursor = String(caption.prefix(cursorPosition - currentWord.count))
        let afterCursor = String(caption.suffix(caption.count - cursorPosition))
        
        caption = beforeCursor + "#\(tag) " + afterCursor
        showHashtags = false
        currentWord = ""
    }
}

// MARK: - Custom Text Editor

#if canImport(UIKit)
struct CaptionTextEditor: UIViewRepresentable {
    @Binding var text: String
    let onWordChange: (String, Int) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = UIColor.label
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.keyboardType = .twitter
        textView.autocorrectionType = .no
        textView.text = text
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: CaptionTextEditor
        
        init(_ parent: CaptionTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            
            // Get current word at cursor
            if let selectedRange = textView.selectedTextRange {
                let cursorPosition = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
                
                // Find word boundaries
                let text = textView.text ?? ""
                let beforeCursor = String(text.prefix(cursorPosition))
                let words = beforeCursor.split(separator: " ", omittingEmptySubsequences: false)
                
                if let lastWord = words.last {
                    let word = String(lastWord)
                    if word.hasPrefix("@") || word.hasPrefix("#") {
                        parent.onWordChange(word, cursorPosition)
                    } else {
                        parent.onWordChange("", cursorPosition)
                    }
                }
            }
        }
    }
}
#else
// Placeholder for non-iOS platforms
struct CaptionTextEditor: View {
    @Binding var text: String
    let onWordChange: (String, Int) -> Void
    
    var body: some View {
        TextEditor(text: $text)
            .font(OlasDesign.Typography.body)
    }
}
#endif

// MARK: - Preview

struct OlasCaptionComposer_Previews: PreviewProvider {
    static var previews: some View {
        OlasCaptionComposer(caption: .constant(""))
            .environmentObject(AppState())
            .padding()
            .background(OlasDesign.Colors.background)
    }
}