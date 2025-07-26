import SwiftUI
import NDKSwift

// MARK: - Rich Text Component

struct OlasRichText: View {
    let content: String
    let tags: [[String]]
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    
    @State private var parsedComponents: [RichTextComponent] = []
    @State private var profileCache: [String: NDKUserProfile] = [:]
    @State private var loadingProfiles: Set<String> = []
    
    var body: some View {
        Text(attributedString)
            .font(OlasDesign.Typography.body)
            .foregroundColor(OlasDesign.Colors.text)
            .tint(Color.white)
            .task {
                parseContent()
                await loadProfiles()
            }
            .onChange(of: content) { _, _ in
                parseContent()
                Task {
                    await loadProfiles()
                }
            }
    }
    
    private var attributedString: AttributedString {
        var result = AttributedString()
        
        for component in parsedComponents {
            switch component {
            case .text(let text):
                result.append(AttributedString(text))
                
            case .mention(let pubkey):
                let displayName = profileCache[pubkey]?.displayName ?? profileCache[pubkey]?.name ?? shortPubkey(pubkey)
                var mention = AttributedString("@\(displayName)")
                mention.foregroundColor = .white
                mention.font = OlasDesign.Typography.bodyMedium
                mention.link = URL(string: "olas://profile/\(pubkey)")
                mention.underlineStyle = .single
                #if os(iOS)
                mention.underlineColor = UIColor.white.withAlphaComponent(0.3)
                #else
                mention.underlineColor = NSColor.white.withAlphaComponent(0.3)
                #endif
                result.append(mention)
                
            case .hashtag(let tag):
                var hashtag = AttributedString("#\(tag)")
                hashtag.foregroundColor = .white
                hashtag.font = OlasDesign.Typography.bodyMedium
                hashtag.link = URL(string: "olas://hashtag/\(tag)")
                hashtag.underlineStyle = .single
                #if os(iOS)
                hashtag.underlineColor = UIColor.white.withAlphaComponent(0.3)
                #else
                hashtag.underlineColor = NSColor.white.withAlphaComponent(0.3)
                #endif
                result.append(hashtag)
                
            case .link(let url):
                var link = AttributedString(url)
                link.foregroundColor = .white.opacity(0.8)
                link.font = OlasDesign.Typography.body
                link.link = URL(string: url)
                link.underlineStyle = .single
                #if os(iOS)
                link.underlineColor = UIColor.white.withAlphaComponent(0.3)
                #else
                link.underlineColor = NSColor.white.withAlphaComponent(0.3)
                #endif
                result.append(link)
                
            case .noteReference(let noteId):
                var reference = AttributedString("📝 Note")
                reference.foregroundColor = .white.opacity(0.8)
                reference.font = OlasDesign.Typography.body
                reference.link = URL(string: "olas://note/\(noteId)")
                reference.underlineStyle = .single
                #if os(iOS)
                reference.underlineColor = UIColor.white.withAlphaComponent(0.3)
                #else
                reference.underlineColor = NSColor.white.withAlphaComponent(0.3)
                #endif
                result.append(reference)
            }
        }
        
        return result
    }
    
    private func parseContent() {
        let currentText = content
        
        // Create a map of replacements with their positions
        var replacements: [(range: Range<String.Index>, component: RichTextComponent)] = []
        
        // Find all mentions from tags
        for tag in tags {
            if tag.count >= 2 && tag[0] == "p" {
                let pubkey = tag[1]
                let mentionIndex = tag.count > 2 ? Int(tag[2]) : nil
                
                // Find nostr: mentions
                let nostrPattern = "nostr:npub1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{58}"
                if let regex = try? NSRegularExpression(pattern: nostrPattern) {
                    let matches = regex.matches(in: currentText, range: NSRange(currentText.startIndex..., in: currentText))
                    for match in matches {
                        if let range = Range(match.range, in: currentText) {
                            let npubFull = String(currentText[range])
                            let npub = npubFull.replacingOccurrences(of: "nostr:", with: "")
                            if let decoded = try? Bech32.decode(npub) {
                                let decodedPubkey = Data(decoded.data).hexString
                                if decodedPubkey == pubkey {
                                    replacements.append((range, .mention(pubkey)))
                                }
                            }
                        }
                    }
                }
                
                // Find #[index] mentions
                if let index = mentionIndex {
                    let indexPattern = "#\\[\(index)\\]"
                    if let regex = try? NSRegularExpression(pattern: indexPattern) {
                        let matches = regex.matches(in: currentText, range: NSRange(currentText.startIndex..., in: currentText))
                        for match in matches {
                            if let range = Range(match.range, in: currentText) {
                                replacements.append((range, .mention(pubkey)))
                            }
                        }
                    }
                }
            }
        }
        
        // Find hashtags
        let hashtagPattern = "#[a-zA-Z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let matches = regex.matches(in: currentText, range: NSRange(currentText.startIndex..., in: currentText))
            for match in matches {
                if let range = Range(match.range, in: currentText) {
                    let hashtag = String(currentText[range]).dropFirst() // Remove #
                    replacements.append((range, .hashtag(String(hashtag))))
                }
            }
        }
        
        // Find URLs
        let urlPattern = "https?://[^\\s]+"
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = regex.matches(in: currentText, range: NSRange(currentText.startIndex..., in: currentText))
            for match in matches {
                if let range = Range(match.range, in: currentText) {
                    let url = String(currentText[range])
                    replacements.append((range, .link(url)))
                }
            }
        }
        
        // Find note references
        let notePattern = "nostr:note1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{58}"
        if let regex = try? NSRegularExpression(pattern: notePattern) {
            let matches = regex.matches(in: currentText, range: NSRange(currentText.startIndex..., in: currentText))
            for match in matches {
                if let range = Range(match.range, in: currentText) {
                    let noteFull = String(currentText[range])
                    let note = noteFull.replacingOccurrences(of: "nostr:", with: "")
                    if let decoded = try? Bech32.decode(note) {
                        let noteId = Data(decoded.data).hexString
                        replacements.append((range, .noteReference(noteId)))
                    }
                }
            }
        }
        
        // Sort replacements by position (reverse order for replacement)
        replacements.sort { $0.range.lowerBound > $1.range.lowerBound }
        
        // Build components
        var workingText = currentText
        var finalComponents: [RichTextComponent] = []
        
        for replacement in replacements {
            // Add text after this replacement
            let afterText = String(workingText[replacement.range.upperBound...])
            if !afterText.isEmpty {
                finalComponents.insert(.text(afterText), at: 0)
            }
            
            // Add the replacement component
            finalComponents.insert(replacement.component, at: 0)
            
            // Update working text
            workingText = String(workingText[..<replacement.range.lowerBound])
        }
        
        // Add any remaining text
        if !workingText.isEmpty {
            finalComponents.insert(.text(workingText), at: 0)
        }
        
        parsedComponents = finalComponents
    }
    
    private func loadProfiles() async {
        guard let profileManager = nostrManager.ndk?.profileManager else { return }
        
        // Find all unique pubkeys that need loading
        let pubkeysToLoad = parsedComponents.compactMap { component -> String? in
            if case .mention(let pubkey) = component,
               profileCache[pubkey] == nil,
               !loadingProfiles.contains(pubkey) {
                return pubkey
            }
            return nil
        }
        
        // Mark as loading
        await MainActor.run {
            pubkeysToLoad.forEach { loadingProfiles.insert($0) }
        }
        
        // Load profiles
        await withTaskGroup(of: (String, NDKUserProfile?).self) { group in
            for pubkey in pubkeysToLoad {
                group.addTask {
                    // Use observe to get reactive updates
                    var profile: NDKUserProfile?
                    for await p in await profileManager.observe(for: pubkey, maxAge: 3600) {
                        profile = p
                        break // Just get the first one for now
                    }
                    return (pubkey, profile)
                }
            }
            
            // Collect results
            for await (pubkey, profile) in group {
                await MainActor.run {
                    if let profile = profile {
                        profileCache[pubkey] = profile
                    }
                    loadingProfiles.remove(pubkey)
                }
            }
        }
    }
    
    private func shortPubkey(_ pubkey: String) -> String {
        if pubkey.count > 8 {
            return "\(pubkey.prefix(4))...\(pubkey.suffix(4))"
        }
        return pubkey
    }
}

// MARK: - Rich Text Component Types

private enum RichTextComponent: Hashable {
    case text(String)
    case mention(String) // pubkey
    case hashtag(String)
    case link(String)
    case noteReference(String) // note id
}

// MARK: - Preview Helper

struct OlasRichText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 20) {
            OlasRichText(
                content: "Hello nostr:npub1234567890abcdef! Check out #nostr and visit https://nostr.com",
                tags: [["p", "1234567890abcdef"]]
            )
            
            OlasRichText(
                content: "Reply to #[0] about #photography with note reference nostr:note1234567890abcdef",
                tags: [["p", "abcdef1234567890", "0"]]
            )
        }
        .padding()
        .background(OlasDesign.Colors.background)
        .environmentObject(AppState())
    }
}