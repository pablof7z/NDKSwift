import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    ProfileHeaderView()
                    
                    // Stats
                    StatsView()
                    
                    // Content Tabs
                    ProfileContentTabs()
                    
                    // Settings Button
                    Button(action: {
                        Task {
                            await appState.logout()
                        }
                    }) {
                        Text("Logout")
                            .foregroundColor(.red)
                    }
                    .padding()
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ProfileHeaderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.highlighterPurple)
            
            Text("@user")
                .font(.highlighterHeadline)
            
            Text("Curious mind exploring ideas")
                .font(.highlighterBody)
                .foregroundColor(.highlighterSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

struct StatsView: View {
    var body: some View {
        HStack(spacing: 40) {
            StatItem(value: "156", label: "Highlights")
            StatItem(value: "42", label: "Curations")
            StatItem(value: "1.2k", label: "Zaps Earned")
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.highlighterHeadline)
                .foregroundColor(.highlighterPurple)
            Text(label)
                .font(.highlighterCaption)
                .foregroundColor(.highlighterSecondaryText)
        }
    }
}

struct ProfileContentTabs: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Picker("Content", selection: $selectedTab) {
                Text("Highlights").tag(0)
                Text("Articles").tag(1)
                Text("Curations").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Content based on selection
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<5) { _ in
                        Text("Content item")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .cardStyle()
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 300)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
