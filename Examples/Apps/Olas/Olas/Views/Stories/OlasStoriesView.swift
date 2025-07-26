import SwiftUI
import NDKSwift

// Wrapper for Int to make it Identifiable
struct StoryIndexWrapper: Identifiable {
    let id: Int
    
    init(_ index: Int) {
        self.id = index
    }
}

struct OlasStoriesView: View {
    @ObservedObject var storiesManager: StoriesManager
    @State private var selectedStoryWrapper: StoryIndexWrapper?
    @State private var showCreateStory = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                // Add Story button
                AddStoryButton(showCreateStory: $showCreateStory)
                
                // User stories
                ForEach(storiesManager.userStories.flatMap { $0.stories }.indices, id: \.self) { index in
                    let allStories = storiesManager.userStories.flatMap { $0.stories }
                    if index < allStories.count {
                        let story = allStories[index]
                        // Convert Story to UserStory for compatibility
                        let userStory = UserStory(
                            user: StoryUser(
                                pubkey: story.authorPubkey,
                                displayName: storiesManager.userStories.first { $0.authorPubkey == story.authorPubkey }?.authorProfile?.name ?? "User",
                                avatarURL: storiesManager.userStories.first { $0.authorPubkey == story.authorPubkey }?.authorProfile?.picture
                            ),
                            imageURL: story.mediaURLs.first,
                            text: story.content,
                            timestamp: story.timestamp,
                            isViewed: storiesManager.isStoryViewed(story.id)
                        )
                        StoryCircle(
                            story: userStory,
                            index: index,
                            selectedStoryIndex: Binding(
                                get: { selectedStoryWrapper?.id == index ? index : nil },
                            set: { _ in selectedStoryWrapper = StoryIndexWrapper(index) }
                        )
                    )
                    }
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
        }
        .frame(height: 100)
        .fullScreenCover(item: $selectedStoryWrapper) { wrapper in
            let allStories = storiesManager.userStories.flatMap { collection in
                collection.stories.map { story in
                    UserStory(
                        user: StoryUser(
                            pubkey: story.authorPubkey,
                            displayName: collection.authorProfile?.name ?? "User",
                            avatarURL: collection.authorProfile?.picture
                        ),
                        imageURL: story.mediaURLs.first,
                        text: story.content,
                        timestamp: story.timestamp,
                        isViewed: storiesManager.isStoryViewed(story.id)
                    )
                }
            }
            OlasStoryViewerView(
                stories: allStories,
                initialIndex: wrapper.id,
                onDismiss: {
                    selectedStoryWrapper = nil
                }
            )
        }
        .sheet(isPresented: $showCreateStory) {
            CreateStoryView(storiesManager: storiesManager)
        }
    }
}

// MARK: - Add Story Button
struct AddStoryButton: View {
    @Binding var showCreateStory: Bool
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xs) {
            ZStack {
                // User avatar placeholder
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                OlasDesign.Colors.primary.opacity(0.2),
                                OlasDesign.Colors.primary.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                
                // Plus icon
                ZStack {
                    Circle()
                        .fill(OlasDesign.Colors.primary)
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .offset(x: 25, y: 25)
            }
            .scaleEffect(isPressed ? 0.95 : 1)
            
            Text("Your Story")
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.text)
        }
        .onTapGesture {
            showCreateStory = true
            OlasDesign.Haptic.selection()
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Story Circle
struct StoryCircle: View {
    let story: UserStory
    let index: Int
    @Binding var selectedStoryIndex: Int?
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xs) {
            ZStack {
                // Gradient ring for unviewed stories
                if !story.isViewed {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.purple,
                                    Color.pink,
                                    Color.orange
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 74, height: 74)
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 74, height: 74)
                }
                
                // User avatar
                if let avatarURL = story.user.avatarURL {
                    AsyncImage(url: URL(string: avatarURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 66, height: 66)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.gray.opacity(0.3),
                                        Color.gray.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 66, height: 66)
                    }
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: Double(story.user.pubkey.prefix(6).hashValue % 360) / 360, saturation: 0.5, brightness: 0.8),
                                    Color(hue: Double(story.user.pubkey.suffix(6).hashValue % 360) / 360, saturation: 0.5, brightness: 0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 66, height: 66)
                        .overlay(
                            Text(story.user.displayName.prefix(1).uppercased())
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1)
            
            Text(story.user.displayName)
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.text)
                .lineLimit(1)
                .frame(width: 70)
        }
        .onTapGesture {
            selectedStoryIndex = index
            OlasDesign.Haptic.selection()
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Story Viewer
struct OlasStoryViewerView: View {
    let stories: [UserStory]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isDragging = false
    
    init(stories: [UserStory], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.stories = stories
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if currentIndex < stories.count {
                StoryView(
                    story: stories[currentIndex],
                    onNext: {
                        if currentIndex < stories.count - 1 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentIndex += 1
                            }
                        } else {
                            onDismiss()
                        }
                    },
                    onPrevious: {
                        if currentIndex > 0 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentIndex -= 1
                            }
                        }
                    },
                    onDismiss: onDismiss
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }
        }
        .offset(y: dragOffset.height)
        .scaleEffect(isDragging ? 0.9 : 1)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
            DragGesture()
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        onDismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }
}

// MARK: - Individual Story View
struct StoryView: View {
    let story: UserStory
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onDismiss: () -> Void
    
    @State private var progress: Double = 0
    @State private var timer: Timer?
    @State private var isPaused = false
    
    let storyDuration: TimeInterval = 5.0
    
    var body: some View {
        ZStack {
            // Story content
            if let imageURL = story.imageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            // Overlay content
            VStack {
                // Progress bars and header
                VStack(spacing: OlasDesign.Spacing.sm) {
                    // Progress indicator
                    ProgressBar(progress: progress)
                        .frame(height: 2)
                        .padding(.horizontal)
                    
                    // Header
                    HStack {
                        // User info
                        HStack(spacing: OlasDesign.Spacing.sm) {
                            if let avatarURL = story.user.avatarURL {
                                AsyncImage(url: URL(string: avatarURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 32, height: 32)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(story.user.displayName)
                                    .font(OlasDesign.Typography.bodyMedium)
                                    .foregroundColor(.white)
                                
                                Text(formatTimeAgo(story.timestamp))
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        Spacer()
                        
                        // Close button
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 50)
                
                Spacer()
                
                // Story text if available
                if let text = story.text {
                    Text(text)
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                .fill(Color.black.opacity(0.6))
                        )
                        .padding()
                }
                
                Spacer()
            }
            
            // Tap areas
            HStack(spacing: 0) {
                // Previous
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onPrevious()
                    }
                
                // Pause/Play
                Color.clear
                    .frame(width: 100)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.1, maximumDistance: .infinity, pressing: { pressing in
                        isPaused = pressing
                    }, perform: {})
                
                // Next
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onNext()
                    }
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        progress = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if !isPaused {
                withAnimation(.linear(duration: 0.05)) {
                    progress += 0.05 / storyDuration
                }
                
                if progress >= 1 {
                    timer?.invalidate()
                    onNext()
                }
            }
        }
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
        }
    }
}

// Removed duplicate StoriesManager and models - using the one from Models/StoriesManager.swift

// MARK: - Models
struct UserStory: Identifiable {
    let id = UUID()
    let user: StoryUser
    let imageURL: String?
    let text: String?
    let timestamp: Date
    let isViewed: Bool
}

struct StoryUser {
    let pubkey: String
    let displayName: String
    let avatarURL: String?
}