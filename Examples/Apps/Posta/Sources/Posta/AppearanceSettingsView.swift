import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @State private var selectedTheme: ThemeManager.Theme
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        self._selectedTheme = State(initialValue: themeManager.currentTheme)
    }
    
    var body: some View {
        List {
            // Theme Selection
            Section("Theme") {
                ForEach(ThemeManager.Theme.allCases, id: \.self) { theme in
                    ThemeRow(
                        theme: theme,
                        isSelected: selectedTheme == theme,
                        onSelect: {
                            selectedTheme = theme
                            themeManager.currentTheme = theme
                        }
                    )
                }
            }
            
            // Preview Section
            Section("Preview") {
                VStack(spacing: 16) {
                    // Sample Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                            
                            VStack(alignment: .leading) {
                                Text("Sample User")
                                    .font(.headline)
                                Text("@sampleuser")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {}) {
                                Text("Follow")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(15)
                            }
                        }
                        
                        Text("This is how your content will appear with the selected theme. The app automatically adjusts colors and contrast for optimal readability.")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 20) {
                            Button(action: {}) {
                                Image(systemName: "heart")
                                    .foregroundColor(.secondary)
                            }
                            Button(action: {}) {
                                Image(systemName: "bubble.left")
                                    .foregroundColor(.secondary)
                            }
                            Button(action: {}) {
                                Image(systemName: "arrow.2.squarepath")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                }
                .padding(.vertical)
            }
            
            // Additional Options
            Section("Display") {
                HStack {
                    Text("App Icon")
                    Spacer()
                    Text("Default")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Text Size")
                    Spacer()
                    Text("Default")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct ThemeRow: View {
    let theme: ThemeManager.Theme
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.rawValue)
                        .font(.headline)
                    
                    Text(themeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var themeDescription: String {
        switch theme {
        case .system:
            return "Automatically match your device settings"
        case .light:
            return "Always use light appearance"
        case .dark:
            return "Always use dark appearance"
        }
    }
}