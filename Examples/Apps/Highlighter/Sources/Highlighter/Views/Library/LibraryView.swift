import SwiftUI
import NDKSwift

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateCuration = false
    @State private var selectedCuration: ArticleCuration?
    @State private var selectedFollowPack: FollowPack?
    @State private var showCurationManagement = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Saved highlights
                    SavedHighlightsSection()
                    
                    // Your curations
                    YourCurationsSection(
                        curations: appState.userCurations,
                        showCreateCuration: $showCreateCuration,
                        selectedCuration: $selectedCuration,
                        showCurationManagement: $showCurationManagement
                    )
                    
                    // Follow packs
                    FollowPacksSection(
                        followPacks: appState.followPacks,
                        selectedFollowPack: $selectedFollowPack
                    )
                }
                .padding(.vertical)
            }
            .background(DesignSystem.Colors.background)
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
        .sheet(isPresented: $showCurationManagement) {
            CurationManagementView()
                .environmentObject(appState)
        }
    }
}

struct SavedHighlightsSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Highlights")
                .font(DesignSystem.Typography.headline)
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
                .foregroundColor(DesignSystem.Colors.primary.opacity(0.5))
            
            Text("No highlights yet")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text("Start highlighting to build your collection")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(DesignSystem.Colors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

struct SavedHighlightCard: View {
    let highlight: HighlightEvent
    @State private var showDetail = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ContentFormatter.formatHighlight(highlight.content))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                if let url = highlight.url {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text(ContentFormatter.extractDomain(from: url))
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundColor(DesignSystem.Colors.primary)
                }
                
                Text(RelativeTimeFormatter.relativeTime(from: highlight.createdAt))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding()
            .frame(width: 250, alignment: .leading)
            .modernCard()
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            HighlightDetailView(highlight: highlight)
        }
    }
    
}

struct YourCurationsSection: View {
    let curations: [ArticleCuration]
    @Binding var showCreateCuration: Bool
    @Binding var selectedCuration: ArticleCuration?
    @Binding var showCurationManagement: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Curations")
                    .font(DesignSystem.Typography.headline)
                
                Spacer()
                
                // Manage button
                if !curations.isEmpty {
                    Button(action: { showCurationManagement = true }) {
                        Label("Manage", systemImage: "folder.badge.gearshape")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.highlighterPurple)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.highlighterPurple.opacity(0.1))
                            .cornerRadius(20)
                    }
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
                
                Button(action: { showCreateCuration = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .symbolEffect(.bounce, value: showCreateCuration)
                }
            }
            .padding(.horizontal)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: curations.isEmpty)
            
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
                .foregroundColor(DesignSystem.Colors.primary.opacity(0.5))
            
            Text("No curations yet")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Button(action: { showCreateCuration = true }) {
                Text("Create Your First Curation")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(DesignSystem.Colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(DesignSystem.Colors.surface.opacity(0.5))
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
                                colors: [DesignSystem.Colors.primary.opacity(0.3), DesignSystem.Colors.secondary.opacity(0.3)],
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
                            colors: [DesignSystem.Colors.primary, DesignSystem.Colors.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 80)
            }
            
            Text(curation.title)
                .font(DesignSystem.Typography.body)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Text("\(curation.articles.count) articles")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .modernCard()
    }
}

struct FollowPacksSection: View {
    let followPacks: [FollowPack]
    @Binding var selectedFollowPack: FollowPack?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Follow Packs")
                .font(DesignSystem.Typography.headline)
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
                .foregroundColor(DesignSystem.Colors.primary.opacity(0.5))
            
            Text("No follow packs discovered yet")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text("Follow packs will appear here as they're discovered")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(DesignSystem.Colors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

struct FollowPackRow: View {
    let followPack: FollowPack
    
    var body: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundColor(DesignSystem.Colors.primary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(followPack.title)
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                
                Text("\(followPack.profiles.count) people")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding()
        .modernCard()
    }
}


#Preview {
    LibraryView()
        .environmentObject(AppState())
}
