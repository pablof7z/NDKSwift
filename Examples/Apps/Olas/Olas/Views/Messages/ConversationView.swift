import SwiftUI
import NDKSwift
#if os(iOS)
import UIKit
#endif

struct ConversationView: View {
    let conversation: Conversation
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ConversationViewModel()
    @State private var messageText = ""
    @State private var showingProfile = false
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isTyping = false
    @FocusState private var isMessageFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Background
            OlasDesign.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: OlasDesign.Spacing.sm) {
                            ForEach(viewModel.messages.reversed()) { message in
                                MessageBubbleView(
                                    message: message,
                                    isFromMe: message.senderPubkey == viewModel.myPubkey
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.vertical, OlasDesign.Spacing.md)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages) { _, _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                
                // Message input
                messageInputView
            }
        }
        .navigationTitle(conversation.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: OlasDesign.Spacing.sm) {
                    OlasAvatar(
                        url: conversation.profile?.picture,
                        size: 32,
                        pubkey: conversation.peerPubkey
                    )
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(conversation.displayName)
                            .font(OlasDesign.Typography.bodyBold)
                            .foregroundColor(OlasDesign.Colors.text)
                        
                        if viewModel.isOnline {
                            Text("Active now")
                                .font(.system(size: 11))
                                .foregroundColor(Color.green)
                        }
                    }
                }
                .onTapGesture {
                    showingProfile = true
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: OlasDesign.Spacing.md) {
                    Button {
                        // TODO: Voice call
                        OlasDesign.Haptic.selection()
                    } label: {
                        Image(systemName: "phone.fill")
                            .foregroundColor(OlasDesign.Colors.primary)
                    }
                    
                    Button {
                        // TODO: Video call
                        OlasDesign.Haptic.selection()
                    } label: {
                        Image(systemName: "video.fill")
                            .foregroundColor(OlasDesign.Colors.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                ProfileView(pubkey: conversation.peerPubkey)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                Task {
                    await sendImage(image)
                }
            }
        }
        .task {
            if let ndk = nostrManager.ndk {
                await viewModel.startObserving(
                    conversation: conversation,
                    ndk: ndk
                )
            }
        }
    }
    
    private var messageInputView: some View {
        VStack(spacing: 0) {
            // Typing indicator
            if viewModel.isPeerTyping {
                HStack(spacing: OlasDesign.Spacing.sm) {
                    OlasAvatar(
                        url: conversation.profile?.picture,
                        size: 24,
                        pubkey: conversation.peerPubkey
                    )
                    
                    TypingIndicatorView()
                    
                    Spacer()
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
                .padding(.vertical, OlasDesign.Spacing.xs)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Input bar
            HStack(spacing: OlasDesign.Spacing.sm) {
                // Camera button
                Button {
                    showingImagePicker = true
                    OlasDesign.Haptic.selection()
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundColor(OlasDesign.Colors.primary)
                }
                
                // Text field
                HStack(spacing: OlasDesign.Spacing.sm) {
                    TextField("Message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                        .focused($isMessageFieldFocused)
                        .lineLimit(1...4)
                        .onChange(of: messageText) { _, _ in
                            updateTypingStatus()
                        }
                    
                    // Emoji button
                    Button {
                        // TODO: Emoji picker
                        OlasDesign.Haptic.selection()
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.title3)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
                .padding(.vertical, OlasDesign.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                        .fill(OlasDesign.Colors.surface)
                )
                
                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: messageText.isEmpty ? "heart.fill" : "paperplane.fill")
                        .font(.title3)
                        .foregroundStyle(
                            messageText.isEmpty ? OlasDesign.Colors.like : 
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(messageText.isEmpty ? 0 : 45))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: messageText.isEmpty)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && messageText != "")
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                OlasDesign.Colors.background
                    .shadow(color: .black.opacity(0.05), radius: 10, y: -5)
            )
        }
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedMessage.isEmpty && messageText.isEmpty {
            // Send heart reaction
            Task {
                await viewModel.sendMessage("❤️")
                OlasDesign.Haptic.success()
            }
        } else if !trimmedMessage.isEmpty {
            // Send text message
            Task {
                await viewModel.sendMessage(trimmedMessage)
                messageText = ""
                OlasDesign.Haptic.success()
            }
        }
    }
    
    private func sendImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        
        // Upload to Blossom
        if let uploadedURLs = try? await nostrManager.blossomManager.uploadData(
            imageData,
            mimeType: "image/jpeg"
        ), let imageURL = uploadedURLs.first {
            await viewModel.sendMessage(imageURL)
            selectedImage = nil
        }
    }
    
    private func updateTypingStatus() {
        // TODO: Implement typing indicators
        isTyping = !messageText.isEmpty
    }
}

// MARK: - Message Bubble
struct MessageBubbleView: View {
    let message: ChatMessage
    let isFromMe: Bool
    @State private var showTimestamp = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: OlasDesign.Spacing.sm) {
            if isFromMe { Spacer(minLength: 60) }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                // Message bubble
                Group {
                    if message.isImage {
                        AsyncImage(url: URL(string: message.content)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 250, maxHeight: 250)
                                .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                .fill(OlasDesign.Colors.surface)
                                .frame(width: 200, height: 200)
                                .overlay(
                                    ProgressView()
                                )
                        }
                    } else if message.content == "❤️" {
                        // Special heart animation
                        Text(message.content)
                            .font(.system(size: 48))
                    } else {
                        Text(message.content)
                            .font(OlasDesign.Typography.body)
                            .foregroundColor(isFromMe ? .white : OlasDesign.Colors.text)
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.vertical, OlasDesign.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                    .fill(
                                        isFromMe ?
                                        LinearGradient(
                                            colors: OlasDesign.Colors.primaryGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) :
                                        LinearGradient(
                                            colors: [OlasDesign.Colors.surface],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showTimestamp.toggle()
                    }
                }
                
                // Timestamp (shown on tap)
                if showTimestamp {
                    HStack(spacing: 4) {
                        Text(message.timestamp.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 11))
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                        
                        if isFromMe && message.isDelivered {
                            Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark")
                                .font(.system(size: 11))
                                .foregroundColor(
                                    message.isRead ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary
                                )
                        }
                    }
                    .transition(.opacity)
                }
            }
            
            if !isFromMe { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var animationAmount = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(OlasDesign.Colors.textSecondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount == Double(index) ? 1.3 : 1)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.sm)
        .padding(.vertical, OlasDesign.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
        .onAppear {
            animationAmount = 2
        }
    }
}

// MARK: - View Model
@MainActor
class ConversationViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isOnline = false
    @Published var isPeerTyping = false
    
    var myPubkey: String = ""
    private var conversation: Conversation?
    private var ndk: NDK?
    private var messageTask: Task<Void, Never>?
    
    func startObserving(conversation: Conversation, ndk: NDK) async {
        self.conversation = conversation
        self.ndk = ndk
        
        if let signer = NDKAuthManager.shared.activeSigner,
           let pubkey = try? await signer.pubkey {
            self.myPubkey = pubkey
        }
        
        // Convert existing messages
        await loadExistingMessages()
        
        // Observe new messages
        await observeNewMessages()
        
        // Check online status
        checkOnlineStatus()
    }
    
    private func loadExistingMessages() async {
        guard let conversation = conversation,
              let ndk = ndk else { return }
        
        // Convert NDKEvents to ChatMessages
        let chatMessages = conversation.messages.compactMap { event -> ChatMessage? in
            guard let content = decryptMessage(event) else { return nil }
            
            return ChatMessage(
                id: event.id,
                content: content,
                senderPubkey: event.pubkey,
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                isDelivered: true,
                isRead: event.pubkey != myPubkey
            )
        }
        
        await MainActor.run {
            self.messages = chatMessages.sorted { $0.timestamp < $1.timestamp }
        }
    }
    
    private func observeNewMessages() async {
        guard let conversation = conversation,
              let ndk = ndk else { return }
        
        let filter = NDKFilter(
            kinds: [4],
            authors: [conversation.peerPubkey, myPubkey],
            since: Timestamp(Date())
        )
        
        messageTask?.cancel()
        messageTask = Task {
            for await event in await ndk.observe(filters: [filter]) {
                if let message = await processIncomingMessage(event) {
                    await MainActor.run {
                        self.messages.append(message)
                        
                        if message.senderPubkey != self.myPubkey {
                            OlasDesign.Haptic.notification()
                        }
                    }
                }
            }
        }
    }
    
    private func processIncomingMessage(_ event: NDKEvent) async -> ChatMessage? {
        guard let content = decryptMessage(event) else { return nil }
        
        return ChatMessage(
            id: event.id,
            content: content,
            senderPubkey: event.pubkey,
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            isDelivered: true,
            isRead: false
        )
    }
    
    func sendMessage(_ content: String) async {
        guard let conversation = conversation,
              let ndk = ndk,
              let signer = NDKAuthManager.shared.activeSigner else { return }
        
        do {
            // Create encrypted DM (NIP-04)
            let encryptedContent = try await encryptMessage(content, toPubkey: conversation.peerPubkey)
            
            let messageEvent = try await NDKEventBuilder(ndk: ndk)
                .kind(4)
                .content(encryptedContent)
                .tags([["p", conversation.peerPubkey]])
                .build(signer: signer)
            
            // Add to local messages immediately
            let chatMessage = ChatMessage(
                id: messageEvent.id,
                content: content,
                senderPubkey: myPubkey,
                timestamp: Date(),
                isDelivered: false,
                isRead: false
            )
            
            await MainActor.run {
                messages.append(chatMessage)
            }
            
            // Publish to relays
            _ = try await ndk.publish(messageEvent)
            
            // Update delivery status
            if let index = messages.firstIndex(where: { $0.id == chatMessage.id }) {
                await MainActor.run {
                    messages[index].isDelivered = true
                }
            }
            
        } catch {
            print("Failed to send message: \(error)")
            OlasDesign.Haptic.error()
        }
    }
    
    private func encryptMessage(_ content: String, toPubkey: String) async throws -> String {
        // TODO: Implement NIP-04 encryption
        // For now, return a placeholder
        return "encrypted:\(content)"
    }
    
    private func decryptMessage(_ event: NDKEvent) -> String? {
        // TODO: Implement NIP-04 decryption
        // For now, return content with prefix removed
        if event.content.hasPrefix("encrypted:") {
            return String(event.content.dropFirst("encrypted:".count))
        }
        return event.content
    }
    
    private func checkOnlineStatus() {
        // TODO: Implement online status checking
        // Could use NIP-25 reactions or custom online status events
        isOnline = Bool.random() // Mock for now
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable {
    let id: String
    let content: String
    let senderPubkey: String
    let timestamp: Date
    var isDelivered: Bool
    var isRead: Bool
    
    var isImage: Bool {
        content.starts(with: "http") && 
        (content.contains(".jpg") || content.contains(".jpeg") || 
         content.contains(".png") || content.contains(".gif") || 
         content.contains(".webp"))
    }
}