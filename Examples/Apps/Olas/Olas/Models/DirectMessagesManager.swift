import Foundation
import SwiftUI
import NDKSwift
import CryptoKit

@MainActor
class DirectMessagesManager: ObservableObject {
    @Published var conversations: [DMConversation] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var currentMessages: [DirectMessage] = []
    
    private let nostrManager: NostrManager
    private var dmTask: Task<Void, Never>?
    private var profileTasks: [String: Task<Void, Never>] = [:]
    
    // NIP-17 Private Direct Messages
    private let dmKind = 1059 // Encrypted direct message
    private let dmNotificationKind = 24133 // DM notification/metadata
    
    init(nostrManager: NostrManager) {
        self.nostrManager = nostrManager
    }
    
    deinit {
        dmTask?.cancel()
        profileTasks.values.forEach { $0.cancel() }
    }
    
    func startObservingMessages() {
        dmTask?.cancel()
        
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer else { return }
        
        dmTask = Task {
            guard let myPubkey = try? await signer.pubkey else { return }
            
            isLoading = true
            
            // Observe encrypted DMs (NIP-17)
            let filter = NDKFilter(
                kinds: [dmKind],
                tags: ["p": Set([myPubkey])] // Messages where I'm tagged
            )
            
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            var messagesByConversation: [String: [DirectMessage]] = [:]
            
            for await event in dataSource.events {
                // Decrypt and process message
                if let message = await decryptMessage(event: event, signer: signer) {
                    let conversationKey = getConversationKey(myPubkey: myPubkey, otherPubkey: message.senderPubkey)
                    
                    if messagesByConversation[conversationKey] == nil {
                        messagesByConversation[conversationKey] = []
                    }
                    messagesByConversation[conversationKey]?.append(message)
                    
                    // Update conversations
                    await updateConversations(from: messagesByConversation, myPubkey: myPubkey)
                    
                    // Load profile for sender
                    loadProfileForPubkey(message.senderPubkey)
                }
            }
            
            isLoading = false
        }
    }
    
    private func decryptMessage(event: NDKEvent, signer: NDKSigner) async -> DirectMessage? {
        // NIP-17 decryption
        // This is a simplified version - real implementation would use NIP-44 encryption
        
        // For now, return a mock message structure
        // TODO: Implement proper NIP-17/NIP-44 decryption
        
        let message = DirectMessage(
            id: event.id,
            senderPubkey: event.pubkey,
            recipientPubkey: "", // Extract from tags
            content: event.content, // This would be decrypted
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            event: event,
            isRead: false,
            mediaAttachments: []
        )
        
        return message
    }
    
    private func getConversationKey(myPubkey: String, otherPubkey: String) -> String {
        // Create consistent conversation key regardless of who sent the message
        let sorted = [myPubkey, otherPubkey].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }
    
    private func updateConversations(from messagesByConversation: [String: [DirectMessage]], myPubkey: String) {
        var updatedConversations: [DMConversation] = []
        
        for (conversationKey, messages) in messagesByConversation {
            let participants = conversationKey.split(separator: "_").map(String.init)
            let otherPubkey = participants.first { $0 != myPubkey } ?? ""
            
            let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
            let lastMessage = sortedMessages.last
            let unreadCount = messages.filter { !$0.isRead && $0.senderPubkey != myPubkey }.count
            
            let conversation = DMConversation(
                id: conversationKey,
                participants: participants,
                messages: sortedMessages,
                lastMessage: lastMessage,
                unreadCount: unreadCount,
                otherParticipantPubkey: otherPubkey
            )
            
            updatedConversations.append(conversation)
        }
        
        // Sort by last message time
        conversations = updatedConversations.sorted {
            ($0.lastMessage?.timestamp ?? Date.distantPast) > ($1.lastMessage?.timestamp ?? Date.distantPast)
        }
        
        // Update total unread count
        unreadCount = conversations.reduce(0) { $0 + $1.unreadCount }
    }
    
    func sendMessage(to recipientPubkey: String, content: String, mediaURLs: [String] = []) async throws {
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer else {
            throw DMError.notAuthenticated
        }
        
        // Create encrypted message content
        let messageContent = DMContent(
            text: content,
            mediaURLs: mediaURLs,
            timestamp: Date()
        )
        
        // Encrypt content (NIP-17/NIP-44)
        // TODO: Implement proper encryption
        let encryptedContent = content // Placeholder
        
        // Create DM event
        let tags: [[String]] = [
            ["p", recipientPubkey], // Recipient
            ["encrypted"] // Mark as encrypted
        ]
        
        let dmEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(dmKind)
            .content(encryptedContent)
            .tags(tags)
            .build(signer: signer)
        
        _ = try await ndk.publish(dmEvent)
        
        // Add to local messages immediately
        let myPubkey = try await signer.pubkey
        let message = DirectMessage(
            id: dmEvent.id,
            senderPubkey: myPubkey,
            recipientPubkey: recipientPubkey,
            content: content,
            timestamp: Date(),
            event: dmEvent,
            isRead: true,
            mediaAttachments: mediaURLs.map { MediaAttachment(url: $0, type: .image) }
        )
        
        // Update conversation
        let conversationKey = getConversationKey(myPubkey: myPubkey, otherPubkey: recipientPubkey)
        if let index = conversations.firstIndex(where: { $0.id == conversationKey }) {
            conversations[index].messages.append(message)
            conversations[index].lastMessage = message
        } else {
            // Create new conversation
            let conversation = DMConversation(
                id: conversationKey,
                participants: [myPubkey, recipientPubkey],
                messages: [message],
                lastMessage: message,
                unreadCount: 0,
                otherParticipantPubkey: recipientPubkey
            )
            conversations.insert(conversation, at: 0)
        }
    }
    
    func markConversationAsRead(_ conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        
        // Mark all messages as read
        for i in conversations[index].messages.indices {
            conversations[index].messages[i].isRead = true
        }
        
        conversations[index].unreadCount = 0
        
        // Update total unread count
        unreadCount = conversations.reduce(0) { $0 + $1.unreadCount }
        
        // Save read status
        saveReadStatus(conversationId: conversationId)
    }
    
    func deleteMessage(_ messageId: String) async throws {
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer else {
            throw DMError.notAuthenticated
        }
        
        // Create deletion event
        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(EventKind.deletion)
            .content("Message deleted")
            .tags([
                ["e", messageId],
                ["k", "\(dmKind)"]
            ])
            .build(signer: signer)
        
        _ = try await ndk.publish(deletionEvent)
        
        // Remove from local state
        for i in conversations.indices {
            conversations[i].messages.removeAll { $0.id == messageId }
        }
    }
    
    func loadConversation(with pubkey: String) async {
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer,
              let myPubkey = try? await signer.pubkey else { return }
        
        let conversationKey = getConversationKey(myPubkey: myPubkey, otherPubkey: pubkey)
        
        if let conversation = conversations.first(where: { $0.id == conversationKey }) {
            currentMessages = conversation.messages
            markConversationAsRead(conversationKey)
        } else {
            currentMessages = []
        }
    }
    
    private func loadProfileForPubkey(_ pubkey: String) {
        guard let profileManager = nostrManager.ndk?.profileManager else { return }
        
        profileTasks[pubkey]?.cancel()
        
        profileTasks[pubkey] = Task {
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                if let profile = profile {
                    // Update conversations with profile
                    for i in conversations.indices {
                        if conversations[i].otherParticipantPubkey == pubkey {
                            conversations[i].otherParticipantProfile = profile
                        }
                    }
                }
                break
            }
        }
    }
    
    private func saveReadStatus(conversationId: String) {
        UserDefaults.standard.set(Date(), forKey: "dm_read_\(conversationId)")
    }
    
    private func loadReadStatus(conversationId: String) -> Date? {
        UserDefaults.standard.object(forKey: "dm_read_\(conversationId)") as? Date
    }
}

// MARK: - Models

struct DMConversation: Identifiable {
    let id: String
    let participants: [String]
    var messages: [DirectMessage]
    var lastMessage: DirectMessage?
    var unreadCount: Int
    let otherParticipantPubkey: String
    var otherParticipantProfile: NDKUserProfile?
    
    var displayName: String {
        otherParticipantProfile?.displayName ?? 
        otherParticipantProfile?.name ?? 
        String(otherParticipantPubkey.prefix(8)) + "..."
    }
    
    var lastMessagePreview: String {
        guard let lastMessage = lastMessage else { return "No messages" }
        
        if lastMessage.mediaAttachments.isEmpty {
            return lastMessage.content
        } else if lastMessage.content.isEmpty {
            return "📷 Photo"
        } else {
            return "📷 \(lastMessage.content)"
        }
    }
}

struct DirectMessage: Identifiable {
    let id: String
    let senderPubkey: String
    let recipientPubkey: String
    let content: String
    let timestamp: Date
    let event: NDKEvent
    var isRead: Bool
    let mediaAttachments: [MediaAttachment]
    var senderProfile: NDKUserProfile?
    
    var isFromMe: Bool {
        // This would check against current user's pubkey
        false
    }
}

struct MediaAttachment: Identifiable {
    let id = UUID()
    let url: String
    let type: MediaType
    let blurhash: String?
    
    init(url: String, type: MediaType, blurhash: String? = nil) {
        self.url = url
        self.type = type
        self.blurhash = blurhash
    }
}

enum MediaType {
    case image
    case video
    case audio
}

struct DMContent: Codable {
    let text: String
    let mediaURLs: [String]
    let timestamp: Date
}

enum DMError: LocalizedError {
    case notAuthenticated
    case encryptionFailed
    case decryptionFailed
    case messageSendFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to send messages"
        case .encryptionFailed:
            return "Failed to encrypt message"
        case .decryptionFailed:
            return "Failed to decrypt message"
        case .messageSendFailed:
            return "Failed to send message"
        }
    }
}