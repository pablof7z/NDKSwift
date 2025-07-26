import Foundation
import NDKSwift

// MARK: - Conversation Model
struct Conversation: Identifiable {
    let id = UUID()
    let peerPubkey: String
    var messages: [NDKEvent]
    var profile: NDKUserProfile?
    let myPubkey: String
    
    var displayName: String {
        profile?.displayName ?? profile?.name ?? String(peerPubkey.prefix(16))
    }
    
    var lastMessage: MessagePreview? {
        guard let event = messages.first else { return nil }
        
        return MessagePreview(
            content: decryptedContent(from: event) ?? "Encrypted message",
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            isFromMe: event.pubkey == myPubkey,
            isRead: true // TODO: Implement read receipts
        )
    }
    
    var unreadCount: Int {
        // TODO: Implement proper unread tracking
        messages.filter { $0.pubkey != myPubkey }.prefix(5).count
    }
    
    mutating func updateLastMessage() {
        // Sort messages by timestamp
        messages.sort { $0.createdAt > $1.createdAt }
    }
    
    private func decryptedContent(from event: NDKEvent) -> String? {
        // TODO: Implement NIP-04 decryption
        // For now, return a placeholder
        return "Message content"
    }
}

// MARK: - Message Preview
struct MessagePreview {
    let content: String
    let timestamp: Date
    let isFromMe: Bool
    let isRead: Bool
}

// MARK: - Active User
struct ActiveUser: Identifiable {
    let id = UUID()
    let pubkey: String
    var profile: NDKUserProfile?
    let lastSeen: Date
}