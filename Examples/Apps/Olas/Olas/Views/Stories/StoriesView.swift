import SwiftUI
import NDKSwift
#if os(iOS)
import UIKit
#endif

struct StoriesView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var stories: [Story] = []
    @State private var selectedStory: Story?
    @State private var showCreateStory = false
    @State private var isLoading = true
    @State private var hasLoadedStories = false
    @State private var storiesManager: StoriesManager?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.md) {
                // Add Story button
                addStoryButton
                
                // Stories
                ForEach(stories) { story in
                    StoryCircleView(story: story) {
                        selectedStory = story
                    }
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
        }
        .frame(height: 100)
        .background(
            LinearGradient(
                colors: [
                    OlasDesign.Colors.background,
                    OlasDesign.Colors.background.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            if storiesManager == nil {
                storiesManager = StoriesManager(nostrManager: nostrManager)
            }
        }
        .task {
            if !hasLoadedStories {
                hasLoadedStories = true
                await loadStories()
            }
        }
        .fullScreenCover(item: $selectedStory) { story in
            StoryViewerView(stories: stories, initialStory: story)
                .environment(nostrManager)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showCreateStory) {
            if let storiesManager = storiesManager {
                CreateStoryView(storiesManager: storiesManager)
                    .environment(nostrManager)
                    .environmentObject(appState)
            }
        }
    }
    
    private var addStoryButton: some View {
        Button {
            showCreateStory = true
            OlasDesign.Haptic.selection()
        } label: {
            VStack(spacing: OlasDesign.Spacing.xs) {
                ZStack {
                    // User avatar
                    if let profilePicture = nostrManager.currentUserProfile?.picture {
                        AsyncImage(url: URL(string: profilePicture)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: OlasDesign.Colors.primaryGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                            .overlay(
                                Text(getUserInitial())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Plus icon
                    Circle()
                        .fill(OlasDesign.Colors.primary)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(OlasDesign.Colors.background, lineWidth: 2)
                        )
                        .offset(x: 25, y: 25)
                }
                
                Text("Your Story")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(1)
            }
        }
    }
    
    private func getUserInitial() -> String {
        // Get current user's profile from storiesManager
        if let currentUser = storiesManager?.currentUserProfile {
            if let name = currentUser.name, !name.isEmpty {
                return String(name.prefix(1)).uppercased()
            } else if let displayName = currentUser.displayName, !displayName.isEmpty {
                return String(displayName.prefix(1)).uppercased()
            }
        }
        
        // Fallback to first character of pubkey if no profile
        if let session = nostrManager.authManager.activeSession {
            return String(session.pubkey.prefix(1)).uppercased()
        }
        
        return "?"
    }
    
    private func loadStories() async {
        guard let ndk = nostrManager.ndk else { return }
        
        isLoading = true
        hasLoadedStories = true
        
        // Stories are kind 30024 events (NIP-51 highlights)
        let filter = NDKFilter(
            kinds: [30024],
            since: Timestamp(Int64(Date().addingTimeInterval(-86400).timeIntervalSince1970)) // Last 24 hours
        )
        
        // Create a data source to fetch events
        let dataSource = ndk.dataSource(filter: filter)
        
        // Collect events until EOSE
        var storyEvents: [NDKEvent] = []
        for await event in dataSource.events {
            storyEvents.append(event)
            // Check if we have enough or should stop
            if storyEvents.count > 100 { break }
        }
        
        // Convert to Story models
        var loadedStories: [Story] = []
        
        for event in storyEvents {
            // Extract story data from event
            let story = Story(from: event)
            loadedStories.append(story)
        }
        
        // Sort by timestamp
        loadedStories.sort { $0.timestamp > $1.timestamp }
        
        await MainActor.run {
            self.stories = loadedStories
            self.isLoading = false
        }
        
        // Load profiles for story authors
        await loadProfiles(for: loadedStories)
    }
    
    private func loadProfiles(for stories: [Story]) async {
        guard let profileManager = nostrManager.ndk?.profileManager else { return }
        
        for story in stories {
            Task {
                for await profile in await profileManager.observe(for: story.authorPubkey, maxAge: 3600) {
                    if let profile = profile {
                        await MainActor.run {
                            if let index = self.stories.firstIndex(where: { $0.id == story.id }) {
                                self.stories[index].authorProfile = profile
                            }
                        }
                    }
                    break
                }
            }
        }
    }
}

struct StoryCircleView: View {
    let story: Story
    let action: () -> Void
    @State private var hasViewed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: OlasDesign.Spacing.xs) {
                ZStack {
                    // Gradient ring
                    Circle()
                        .stroke(
                            hasViewed ?
                            LinearGradient(
                                colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient + [Color(hex: "FFD54F")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 74, height: 74)
                    
                    // Avatar
                    if let picture = story.authorProfile?.picture {
                        AsyncImage(url: URL(string: picture)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 66, height: 66)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 66, height: 66)
                            .overlay(
                                Text(String(story.authorProfile?.name?.first ?? "?").uppercased())
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                Text(story.authorProfile?.name ?? "Loading...")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
    }
}

// MARK: - Story Model

struct Story: Identifiable {
    let id: String
    let authorPubkey: String
    var authorProfile: NDKUserProfile?
    let content: String
    let mediaURLs: [String]
    let timestamp: Date
    let event: NDKEvent
    
    init(from event: NDKEvent) {
        self.id = event.id
        self.authorPubkey = event.pubkey
        self.content = event.content
        self.mediaURLs = event.imageURLs
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        self.event = event
    }
}

// MARK: - Story Viewer

struct StoryViewerView: View {
    let stories: [Story]
    let initialStory: Story
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var progress: Double = 0
    @State private var timer: Timer?
    @State private var isPaused = false
    
    init(stories: [Story], initialStory: Story) {
        self.stories = stories
        self.initialStory = initialStory
        self._currentIndex = State(initialValue: stories.firstIndex(where: { $0.id == initialStory.id }) ?? 0)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            // Story content
            if currentIndex < stories.count {
                StoryContentView(story: stories[currentIndex])
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
            
            // Progress bars
            VStack {
                HStack(spacing: 4) {
                    ForEach(0..<stories.count, id: \.self) { index in
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 3)
                                
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: progressWidth(for: index, totalWidth: geometry.size.width), height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                Spacer()
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
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
                        previousStory()
                    }
                
                // Next
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        nextStory()
                    }
            }
            .gesture(
                DragGesture()
                    .onChanged { _ in
                        isPaused = true
                    }
                    .onEnded { value in
                        isPaused = false
                        if value.translation.height > 100 {
                            dismiss()
                        }
                    }
            )
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func progressWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < currentIndex {
            return totalWidth
        } else if index == currentIndex {
            return totalWidth * progress
        } else {
            return 0
        }
    }
    
    private func startTimer() {
        progress = 0
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if !isPaused {
                withAnimation(.linear(duration: 0.05)) {
                    progress += 0.01
                    
                    if progress >= 1 {
                        nextStory()
                    }
                }
            }
        }
    }
    
    private func nextStory() {
        withAnimation {
            if currentIndex < stories.count - 1 {
                currentIndex += 1
                startTimer()
            } else {
                dismiss()
            }
        }
    }
    
    private func previousStory() {
        withAnimation {
            if currentIndex > 0 {
                currentIndex -= 1
                startTimer()
            }
        }
    }
}

struct StoryContentView: View {
    let story: Story
    
    var body: some View {
        ZStack {
            // Media
            if let firstImage = story.mediaURLs.first {
                AsyncImage(url: URL(string: firstImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            } else {
                // Text-only story
                LinearGradient(
                    colors: OlasDesign.Colors.primaryGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Content overlay
            VStack {
                // Author info
                HStack(spacing: OlasDesign.Spacing.sm) {
                    OlasAvatar(
                        url: story.authorProfile?.picture,
                        size: 40,
                        pubkey: story.authorPubkey
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(story.authorProfile?.displayName ?? story.authorProfile?.name ?? "Loading...")
                            .font(OlasDesign.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Text(RelativeTimeFormatter.format(story.timestamp))
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // Caption
                if !story.content.isEmpty {
                    Text(story.content)
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            Color.black.opacity(0.6)
                                .blur(radius: 20)
                        )
                        .padding()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Create Story View
// Moved to CreateStoryView.swift
/*
struct CreateStoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @State private var selectedImage: UIImage?
    @State private var caption = ""
    @State private var isPosting = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                if let image = selectedImage {
                    // Preview
                    VStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 400)
                            .cornerRadius(OlasDesign.CornerRadius.lg)
                        
                        TextField("Add a caption...", text: $caption)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(OlasDesign.Typography.body)
                            .foregroundColor(OlasDesign.Colors.text)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                    .fill(OlasDesign.Colors.surface)
                            )
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.top)
                } else {
                    // Image selection
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        Spacer()
                        
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: OlasDesign.Colors.primaryGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Create Your Story")
                            .font(OlasDesign.Typography.title)
                            .foregroundStyle(OlasDesign.Colors.text)
                        
                        VStack(spacing: OlasDesign.Spacing.md) {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera.fill")
                                    .font(OlasDesign.Typography.bodyMedium)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: OlasDesign.Colors.primaryGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
                            }
                            
                            Button {
                                showingImagePicker = true
                            } label: {
                                Label("Choose from Library", systemImage: "photo.fill")
                                    .font(OlasDesign.Typography.bodyMedium)
                                    .foregroundStyle(OlasDesign.Colors.text)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                            .fill(OlasDesign.Colors.surface)
                                    )
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.xl)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("New Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if selectedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Share") {
                            Task {
                                await postStory()
                            }
                        }
                        .disabled(isPosting)
                        .font(OlasDesign.Typography.bodyBold)
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: $selectedImage)
            }
            .overlay {
                if isPosting {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: OlasDesign.Spacing.md) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Posting story...")
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(.white)
                        }
                        .padding(OlasDesign.Spacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                .fill(OlasDesign.Colors.surface)
                        )
                    }
                }
            }
        }
    }
    
    private func postStory() async {
        guard let image = selectedImage,
              let ndk = nostrManager.ndk,
              let signer = NDKAuthManager.shared.activeSigner else { return }
        
        isPosting = true
        
        do {
            // Upload image to Blossom
            let imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
            let uploadedURLs = try await nostrManager.blossomManager.uploadData(
                imageData,
                mimeType: "image/jpeg"
            )
            
            guard let imageURL = uploadedURLs.first else {
                throw NSError(domain: "StoryUpload", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to upload image"])
            }
            
            // Create story event (kind 30024)
            let tags: [[String]] = [
                ["d", "story-\(UUID().uuidString)"],
                ["title", "Story"],
                ["image", imageURL],
                ["published_at", "\(Int(Date().timeIntervalSince1970))"],
                ["expiration", "\(Int(Date().addingTimeInterval(86400).timeIntervalSince1970))"] // 24 hours
            ]
            
            let storyEvent = try await NDKEventBuilder(ndk: ndk)
                .kind(30024)
                .content(caption)
                .tags(tags)
                .build(signer: signer)
            
            _ = try await ndk.publish(storyEvent)
            
            OlasDesign.Haptic.success()
            dismiss()
        } catch {
            print("Failed to post story: \(error)")
            OlasDesign.Haptic.error()
        }
        
        isPosting = false
    }
}
*/

// MARK: - Image Pickers
// Moved to CreateStoryView.swift
/*
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
*/

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}