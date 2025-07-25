import SwiftUI
import NDKSwift

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedTab = DiscoveryTab.articles
    
    enum DiscoveryTab: String, CaseIterable {
        case articles = "Articles"
        case highlights = "Highlights"
        case curations = "Collections"
        case users = "Users"
        
        var icon: String {
            switch self {
            case .articles: return "doc.text"
            case .highlights: return "highlighter"
            case .curations: return "folder"
            case .users: return "person.2"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector
                Divider()
                contentView
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: searchPrompt)
        }
    }
    
    @ViewBuilder
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DiscoveryTab.allCases, id: \.self) { tab in
                    SearchTabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(AnimationSystem.Curves.springSnappy) {
                            selectedTab = tab
                        }
                        HapticManager.shared.triggerSelection()
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .articles:
            ArticleDiscoveryView(searchText: searchText)
        case .highlights:
            HighlightDiscoveryView(searchText: searchText)
        case .curations:
            CurationDiscoveryView(searchText: searchText)
        case .users:
            UserDiscoveryView(searchText: searchText)
        }
    }
    
    private var searchPrompt: String {
        switch selectedTab {
        case .articles: return "Search articles"
        case .highlights: return "Search highlights"
        case .curations: return "Search collections"
        case .users: return "Search users"
        }
    }
}

// MARK: - Tab Button

struct SearchTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : DesignSystem.Colors.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? DesignSystem.Colors.primary : Color(UIColor.systemGray).opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}