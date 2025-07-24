import SwiftUI
import NDKSwift

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateCuration = false
    @State private var selectedCuration: ArticleCuration?
    @State private var selectedFollowPack: FollowPack?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Saved highlights
                    SavedHighlightsSection()
                    
                    // Your curations
                    YourCurationsSection(
                        curations: appState.curations,
                        showCreateCuration: $showCreateCuration,
                        selectedCuration: $selectedCuration
                    )
                    
                    // Follow packs
                    FollowPacksSection(
                        followPacks: appState.followPacks,
                        selectedFollowPack: $selectedFollowPack
                    )
                }
                .padding(.vertical)
            }
            .background(Color.highlighterBackground)
            .navigationTitle("Library")
        }
        .sheet(isPresented: $showCreateCuration) {
            CreateCurationView()
                .environmentObject(appState)
        }
        .sheet(item: $selectedCuration) { curation in
            CurationDetailView(curation: curation)
                .environmentObject(appState)
        }
        .sheet(item: $selectedFollowPack) { followPack in
            FollowPackDetailView(followPack: followPack)
                .environmentObject(appState)
        }
    }
}

struct SavedHighlightsSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Highlights")
                .font(.highlighterHeadline)
                .padding(.horizontal)
            
            if appState.highlights.isEmpty {
                EmptyHighlightsPlaceholder()
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(appState.highlights.prefix(10)) { highlight in
                            SavedHighlightCard(highlight: highlight)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct EmptyHighlightsPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "highlighter")
                .font(.system(size: 48))
                .foregroundColor(.highlighterPurple.opacity(0.5))
            
            Text("No highlights yet")
                .font(.highlighterBody)
                .foregroundColor(.highlighterSecondaryText)
            
            Text("Start highlighting to build your collection")
                .font(.highlighterCaption)
                .foregroundColor(.highlighterSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.highlighterCardBackground.opacity(0.5))
        .cornerRadius(12)
    }
}

struct SavedHighlightCard: View {
    let highlight: HighlightEvent
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\"\(highlight.content)\"")
                    .font(.highlighterBody)
                    .foregroundColor(.highlighterText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                if let url = highlight.url {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text(URL(string: url)?.host ?? "Source")
                            .font(.highlighterCaption)
                    }
                    .foregroundColor(.highlighterPurple)
                }
                
                Text(relativeTime(from: highlight.createdAt))
                    .font(.highlighterCaption)
                    .foregroundColor(.highlighterSecondaryText)
            }
            .padding()
            .frame(width: 250, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            HighlightDetailView(highlight: highlight)
        }
    }
    
    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct YourCurationsSection: View {
    let curations: [ArticleCuration]
    @Binding var showCreateCuration: Bool
    @Binding var selectedCuration: ArticleCuration?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Curations")
                    .font(.highlighterHeadline)
                
                Spacer()
                
                Button(action: { showCreateCuration = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.highlighterPurple)
                }
            }
            .padding(.horizontal)
            
            if curations.isEmpty {
                EmptyCurationsPlaceholder(showCreateCuration: $showCreateCuration)
                    .padding(.horizontal)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(curations) { curation in
                        LibraryCurationCard(curation: curation)
                            .onTapGesture {
                                selectedCuration = curation
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct EmptyCurationsPlaceholder: View {
    @Binding var showCreateCuration: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.highlighterPurple.opacity(0.5))
            
            Text("No curations yet")
                .font(.highlighterBody)
                .foregroundColor(.highlighterSecondaryText)
            
            Button(action: { showCreateCuration = true }) {
                Text("Create Your First Curation")
                    .font(.highlighterCaption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.highlighterPurple)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.highlighterCardBackground.opacity(0.5))
        .cornerRadius(12)
    }
}

struct LibraryCurationCard: View {
    let curation: ArticleCuration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageUrl = curation.image, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.highlighterPurple.opacity(0.3), .highlighterOrange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(height: 80)
                .clipped()
                .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.highlighterPurple, .highlighterOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 80)
            }
            
            Text(curation.title)
                .font(.highlighterBody)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Text("\(curation.articles.count) articles")
                .font(.highlighterCaption)
                .foregroundColor(.highlighterSecondaryText)
        }
        .cardStyle()
    }
}

struct FollowPacksSection: View {
    let followPacks: [FollowPack]
    @Binding var selectedFollowPack: FollowPack?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Follow Packs")
                .font(.highlighterHeadline)
                .padding(.horizontal)
            
            if followPacks.isEmpty {
                EmptyFollowPacksPlaceholder()
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ForEach(followPacks) { pack in
                        FollowPackRow(followPack: pack)
                            .onTapGesture {
                                selectedFollowPack = pack
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct EmptyFollowPacksPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundColor(.highlighterPurple.opacity(0.5))
            
            Text("No follow packs discovered yet")
                .font(.highlighterBody)
                .foregroundColor(.highlighterSecondaryText)
            
            Text("Follow packs will appear here as they're discovered")
                .font(.highlighterCaption)
                .foregroundColor(.highlighterSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.highlighterCardBackground.opacity(0.5))
        .cornerRadius(12)
    }
}

struct FollowPackRow: View {
    let followPack: FollowPack
    
    var body: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundColor(.highlighterPurple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(followPack.title)
                    .font(.highlighterBody)
                    .fontWeight(.medium)
                
                Text("\(followPack.profiles.count) people")
                    .font(.highlighterCaption)
                    .foregroundColor(.highlighterSecondaryText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.highlighterSecondaryText)
        }
        .padding()
        .cardStyle()
    }
}


#Preview {
    LibraryView()
        .environmentObject(AppState())
}