import SwiftUI
import NDKSwift

struct StoriesContainerView: View {
    @Environment(NostrManager.self) private var nostrManager
    @StateObject private var storiesManager: StoriesManager
    
    init() {
        // Initialize StoriesManager with a temporary placeholder
        // We'll update it with the actual NostrManager in onAppear
        let tempManager = NostrManager()
        self._storiesManager = StateObject(wrappedValue: StoriesManager(nostrManager: tempManager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if storiesManager.userStories.isEmpty && !storiesManager.isLoading {
                // Empty state
                emptyStoriesView
            } else {
                OlasStoriesView(storiesManager: storiesManager)
            }
        }
        .frame(height: 120)
        .background(OlasDesign.Colors.background)
        .onAppear {
            storiesManager.startObservingStories()
        }
    }
    
    private var emptyStoriesView: some View {
        VStack(spacing: OlasDesign.Spacing.sm) {
            Spacer()
            
            HStack(spacing: OlasDesign.Spacing.md) {
                // Add story button
                AddStoryButton(showCreateStory: .constant(false))
                    .disabled(true)
                    .opacity(0.7)
                
                // Placeholder circles
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: OlasDesign.Spacing.xs) {
                        Circle()
                            .fill(OlasDesign.Colors.surface)
                            .frame(width: 70, height: 70)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(OlasDesign.Colors.surface)
                            .frame(width: 50, height: 10)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            
            Spacer()
        }
    }
}