import SwiftUI
import NDKSwift

struct MessagesListView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var dmManager: DirectMessagesManager
    @State private var searchText = ""
    @State private var showNewMessage = false
    @State private var selectedConversation: DMConversation?
    
    init(nostrManager: NostrManager) {
        self._dmManager = StateObject(wrappedValue: DirectMessagesManager(nostrManager: nostrManager))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        OlasDesign.Colors.background,
                        OlasDesign.Colors.background.opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if dmManager.conversations.isEmpty && !dmManager.isLoading {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredConversations) { conversation in
                                ConversationRow(
                                    conversation: conversation,
                                    onTap: {
                                        selectedConversation = conversation
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .push(from: .trailing).combined(with: .opacity),
                                    removal: .push(from: .leading).combined(with: .opacity)
                                ))
                                
                                if conversation.id != filteredConversations.last?.id {
                                    Divider()
                                        .padding(.leading, 80)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .refreshable {
                        await refreshMessages()
                    }
                }
                
                // Floating new message button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showNewMessage = true
                            OlasDesign.Haptic.selection()
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    LinearGradient(
                                        colors: OlasDesign.Colors.primaryGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: OlasDesign.Colors.primary.opacity(0.3), radius: 10, y: 5)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if dmManager.unreadCount > 0 {
                        Text("\(dmManager.unreadCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(OlasDesign.Colors.error)
                            )
                    }
                }
            }
            .task {
                dmManager.startObservingMessages()
            }
            .sheet(isPresented: $showNewMessage) {
                NewMessageView(dmManager: dmManager)
                    .environment(nostrManager)
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                ConversationView(
                    conversation: conversation,
                    dmManager: dmManager
                )
                .environment(nostrManager)
            }
        }
    }
    
    private var filteredConversations: [DMConversation] {
        if searchText.isEmpty {
            return dmManager.conversations
        }
        
        return dmManager.conversations.filter { conversation in
            conversation.displayName.localizedCaseInsensitiveContains(searchText) ||
            conversation.lastMessagePreview.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: OlasDesign.Spacing.xl) {
            Spacer()
            
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("No Conversations")
                .font(OlasDesign.Typography.title)
                .foregroundColor(OlasDesign.Colors.text)
            
            Text("Start a conversation with someone")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showNewMessage = true
                OlasDesign.Haptic.selection()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Message")
                }
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundColor(.white)
                .padding(.horizontal, OlasDesign.Spacing.lg)
                .padding(.vertical, OlasDesign.Spacing.md)
                .background(
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
    }
    
    private func refreshMessages() async {
        OlasDesign.Haptic.selection()
        dmManager.startObservingMessages()
        
        // Simulate refresh delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

struct ConversationRow: View {
    let conversation: DMConversation
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            OlasDesign.Haptic.selection()
            onTap()
        }) {
            HStack(spacing: OlasDesign.Spacing.md) {
                // Avatar
                OlasAvatar(
                    url: conversation.otherParticipantProfile?.picture,
                    size: 56,
                    pubkey: conversation.otherParticipantPubkey
                )
                .overlay(
                    // Online indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(OlasDesign.Colors.background, lineWidth: 2)
                        )
                        .offset(x: 20, y: 20)
                        .opacity(Bool.random() ? 1 : 0) // Mock online status
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.displayName)
                            .font(OlasDesign.Typography.bodyMedium)
                            .foregroundColor(OlasDesign.Colors.text)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let timestamp = conversation.lastMessage?.timestamp {
                            Text(formatRelativeTime(timestamp))
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                        }
                    }
                    
                    HStack {
                        Text(conversation.lastMessagePreview)
                            .font(OlasDesign.Typography.body)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        if conversation.unreadCount > 0 {
                            Text("\(conversation.unreadCount)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(minWidth: 20)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(OlasDesign.Colors.primary)
                                )
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                conversation.unreadCount > 0 ?
                OlasDesign.Colors.primary.opacity(0.05) :
                Color.clear
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}