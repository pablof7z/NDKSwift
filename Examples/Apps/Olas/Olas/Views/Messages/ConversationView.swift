import SwiftUI
import NDKSwift
import PhotosUI

struct ConversationView: View {
    let conversation: DMConversation
    @ObservedObject var dmManager: DirectMessagesManager
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var messageText = ""
    @State private var isTyping = false
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var attachedImageData: Data?
    @State private var attachedImageURL: String?
    @State private var showingActionSheet = false
    @State private var selectedMessage: DirectMessage?
    @State private var keyboardHeight: CGFloat = 0
    
    @FocusState private var isMessageFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: OlasDesign.Spacing.sm) {
                        ForEach(dmManager.currentMessages) { message in
                            MessageBubble(
                                message: message,
                                isFromMe: message.senderPubkey == nostrManager.currentUserPubkey,
                                onLongPress: {
                                    selectedMessage = message
                                    showingActionSheet = true
                                    OlasDesign.Haptic.selection()
                                }
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: dmManager.currentMessages.count) { _, _ in
                    withAnimation {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            
            // Input area
            messageInputArea
        }
        .navigationTitle(conversation.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Video call button
                    Button(action: {
                        OlasDesign.Haptic.selection()
                        // TODO: Implement video call
                    }) {
                        Image(systemName: "video.fill")
                            .foregroundColor(OlasDesign.Colors.primary)
                    }
                    
                    // Audio call button
                    Button(action: {
                        OlasDesign.Haptic.selection()
                        // TODO: Implement audio call
                    }) {
                        Image(systemName: "phone.fill")
                            .foregroundColor(OlasDesign.Colors.primary)
                    }
                }
            }
        }
        .task {
            await dmManager.loadConversation(with: conversation.otherParticipantPubkey)
        }
        .confirmationDialog("Message Options", isPresented: $showingActionSheet, presenting: selectedMessage) { message in
            Button("Copy") {
                UIPasteboard.general.string = message.content
                OlasDesign.Haptic.success()
            }
            
            if message.senderPubkey == nostrManager.currentUserPubkey {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await dmManager.deleteMessage(message.id)
                    }
                }
            }
            
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedImage,
            matching: .images
        )
        .onChange(of: selectedImage) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                    attachedImageData = data
                    // Upload to Blossom
                    await uploadImage(data)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
    
    private var messageInputArea: some View {
        VStack(spacing: 0) {
            // Attached image preview
            if let imageData = attachedImageData,
               let uiImage = UIImage(data: imageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(12)
                        .overlay(
                            Button(action: {
                                attachedImageData = nil
                                attachedImageURL = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                            .offset(x: -8, y: -8),
                            alignment: .topTrailing
                        )
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            HStack(spacing: OlasDesign.Spacing.sm) {
                // Attachment button
                Button(action: {
                    showImagePicker = true
                    OlasDesign.Haptic.selection()
                }) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundColor(OlasDesign.Colors.primary)
                }
                
                // Message field
                HStack {
                    TextField("Message", text: $messageText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                        .focused($isMessageFieldFocused)
                        .onChange(of: messageText) { _, newValue in
                            isTyping = !newValue.isEmpty
                        }
                        .onSubmit {
                            if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sendMessage()
                            }
                        }
                    
                    if isTyping {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(OlasDesign.Colors.primary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
                .padding(.vertical, OlasDesign.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(OlasDesign.Colors.surface)
                )
            }
            .padding(.horizontal)
            .padding(.vertical, OlasDesign.Spacing.sm)
        }
        .background(OlasDesign.Colors.background.opacity(0.95))
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty || attachedImageURL != nil else { return }
        
        OlasDesign.Haptic.selection()
        
        Task {
            do {
                var mediaURLs: [String] = []
                if let imageURL = attachedImageURL {
                    mediaURLs.append(imageURL)
                }
                
                try await dmManager.sendMessage(
                    to: conversation.otherParticipantPubkey,
                    content: trimmedMessage,
                    mediaURLs: mediaURLs
                )
                
                // Clear input
                messageText = ""
                attachedImageData = nil
                attachedImageURL = nil
                isMessageFieldFocused = false
            } catch {
                print("Failed to send message: \(error)")
                OlasDesign.Haptic.error()
            }
        }
    }
    
    private func uploadImage(_ data: Data) async {
        // Upload to Blossom
        do {
            let urls = try await nostrManager.blossomManager.uploadData(
                data,
                mimeType: "image/jpeg"
            )
            
            if let url = urls.first {
                attachedImageURL = url
            }
        } catch {
            print("Failed to upload image: \(error)")
            attachedImageData = nil
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = dmManager.currentMessages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

struct MessageBubble: View {
    let message: DirectMessage
    let isFromMe: Bool
    let onLongPress: () -> Void
    
    @State private var showFullImage = false
    @State private var selectedImageURL: String?
    
    var body: some View {
        HStack {
            if isFromMe { Spacer() }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                // Media attachments
                if !message.mediaAttachments.isEmpty {
                    ForEach(message.mediaAttachments) { attachment in
                        if attachment.type == .image {
                            AsyncImage(url: URL(string: attachment.url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: 250, maxHeight: 300)
                                    .clipped()
                                    .cornerRadius(16)
                                    .onTapGesture {
                                        selectedImageURL = attachment.url
                                        showFullImage = true
                                        OlasDesign.Haptic.selection()
                                    }
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 250, height: 200)
                                    .overlay(
                                        ProgressView()
                                    )
                            }
                        }
                    }
                }
                
                // Text content
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(isFromMe ? .white : OlasDesign.Colors.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
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
                
                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .padding(.horizontal, 4)
            }
            .contextMenu {
                Button(action: {
                    UIPasteboard.general.string = message.content
                    OlasDesign.Haptic.success()
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                if isFromMe {
                    Button(role: .destructive, action: onLongPress) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            
            if !isFromMe { Spacer() }
        }
        .padding(.horizontal, 4)
        .fullScreenCover(isPresented: $showFullImage) {
            if let imageURL = selectedImageURL {
                FullScreenImageViewer(imageURL: imageURL)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct FullScreenImageViewer: View {
    let imageURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                
                                // Limit zoom
                                withAnimation(.spring()) {
                                    if scale < 1 {
                                        scale = 1
                                        lastScale = 1
                                        offset = .zero
                                    } else if scale > 5 {
                                        scale = 5
                                        lastScale = 5
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: value.translation.width,
                                    height: value.translation.height
                                )
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    if scale <= 1 {
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1 {
                                scale = 1
                                lastScale = 1
                                offset = .zero
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
            } placeholder: {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
    }
}